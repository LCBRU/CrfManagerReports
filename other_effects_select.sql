SELECT
    @SectionIdx=1,
    @SectionStartDate=@StartDate,
    @SectionEndDate=DATEADD(month,1,@StartDate),
    @TotalSections=DATEDIFF(month,@StartDate,@EndDate);

DECLARE @Idx INT;
DECLARE @Count INT;

DECLARE @ResourceID UNIQUEIDENTIFIER;
DECLARE @EventStartDate DATETIME;
DECLARE @EventEndDate DATETIME;


CREATE TABLE #OtherEvents
(
    Idx INT IDENTITY(1,1),
    SectionIndex INT,
    SectionStartDate DATETIME,
    SectionEndDate DATETIME,
    ResourceID UNIQUEIDENTIFIER,
    OwnerID UNIQUEIDENTIFIER,
    ResourceName NVARCHAR(100),
    StartDate DATETIME,
    EndDate DATETIME,
    Days INT,
    DayStartMinutes INT,
    DayEndMinutes INT,
    MinutesInCoreHours INT DEFAULT 0,
    MinutesOutCoreHours INT DEFAULT 0,
    CorrectedMinutesInCoreHours INT DEFAULT 0,
    DateLabel VARCHAR(10),
    ReportStatus BIT DEFAULT 1
)

WHILE (@SectionIdx&lt;=@TotalSections)
BEGIN

    /** Get all bookings overlapping or within the range */
    INSERT INTO #OtherEvents (SectionIndex,SectionStartDate,SectionEndDate,ResourceID,OwnerID,ResourceName,StartDate,EndDate)
    SELECT
        @SectionIdx,
        @SectionStartDate,
        @SectionEndDate,
        VRE.ResourceID,
        VRE.ROwnerID,
        ResourceName,
        TStartDate,
        TEndDate
    FROM view_ResourceEvents VRE
    INNER JOIN @Resources R ON VRE.ResourceID=R.ResourceID
    INNER JOIN @OtherEventStatus OS ON VRE.REStatusID=OS.StatusID
    WHERE (VRE.REAreaID&lt;&gt;301)
        AND (TEndDate>=@SectionStartDate)
        AND (TStartDate&lt;@SectionEndDate)
    ORDER BY TStartDate;

    /** Get all owner closures - this allows these to be processed with all other non-patient events */
    INSERT INTO #OtherEvents (SectionIndex,SectionStartDate,SectionEndDate,ResourceID,OwnerID,ResourceName,StartDate,EndDate)
    SELECT
        @SectionIdx,
        @SectionStartDate,
        @SectionEndDate,
        VR.ResourceID,
        VRE.ROwnerID,
        VR.ResourceName,
        TStartDate,
        TEndDate
    FROM view_ResourceEvents VRE
    INNER JOIN @Resources R ON VRE.ResourceID=R.ROwnerID
    INNER JOIN view_Resources VR ON VR.ResourceID=R.ResourceID
    WHERE (VRE.REAreaID&lt;&gt;301)
        AND (VRE.REStatusID=@ClosedStatusID)
        AND (TEndDate>=@SectionStartDate) AND (TStartDate&lt;@SectionEndDate)
    ORDER BY TStartDate;

    /** Truncate events overlapping the range to be within the range. Events crossing more than one range will
    be sub-divided accordingly */
    UPDATE #OtherEvents
    SET StartDate = CASE
        WHEN StartDate&lt;@SectionStartDate THEN @SectionStartDate
        ELSE StartDate
    END,
    EndDate = CASE
        WHEN EndDate&gt;@SectionEndDate THEN @SectionEndDate
        ELSE EndDate
    END
    WHERE (SectionIndex=@SectionIdx);

    SET @SectionIdx=@SectionIdx+1;

    SELECT
    @SectionStartDate=DATEADD(month,1,@SectionStartDate),
    @SectionEndDate=DATEADD(month,1,@SectionEndDate);
END;


/** Set the general details for each event. */
UPDATE #OtherEvents
SET DateLabel = CONVERT(VARCHAR(10),StartDate,103)


/** Calculate core hours */
/** Combine overlapping events into single event.*/
DECLARE @OtherOverlaps TABLE
(
    Idx INT NOT NULL UNIQUE,
    ResourceID UNIQUEIDENTIFIER NOT NULL,
    StartDate DATETIME NOT NULL,
    EndDate DATETIME NOT NULL
)

SELECT @Idx=1, @Count=COUNT(1)
FROM #OtherEvents;

WHILE (@Idx&lt;=@Count)
BEGIN
    SET @ResourceID=NULL;

    SELECT
        @ResourceID=ResourceID,
        @EventStartDate=StartDate,
        @EventEndDate=EndDate
    FROM #OtherEvents
    WHERE (Idx=@Idx)
    AND (ReportStatus=1);

    IF (@ResourceID IS NOT NULL)
    BEGIN
        INSERT INTO @OtherOverlaps(Idx,ResourceID,StartDate,EndDate)
        SELECT
            Idx,
            ResourceID,
            StartDate,
            EndDate
        FROM #OtherEvents
        WHERE (ReportStatus=1)
        AND (ResourceID=@ResourceID)
        AND (EndDate&gt;@EventStartDate)
        AND (StartDate&lt;@EventEndDate);

        IF EXISTS(SELECT * FROM @OtherOverlaps HAVING COUNT(*)&gt;0)
        BEGIN
            UPDATE #OtherEvents
            SET ReportStatus=0
            WHERE Idx IN (SELECT Idx FROM @OtherOverlaps);

            INSERT INTO #OtherEvents (SectionIndex,SectionStartDate,SectionEndDate,ResourceID,OwnerID,ResourceName,StartDate,EndDate)
            SELECT
                SectionIndex,
                SectionStartDate,
                SectionEndDate,
                ResourceID,
                OwnerID,
                ResourceName,
                (SELECT MIN(StartDate) FROM @OtherOverlaps),
                (SELECT MAX(EndDate) FROM @OtherOverlaps)
            FROM #OtherEvents
            WHERE (Idx=@Idx);

        END;

        DELETE FROM @OtherOverlaps;
    END

    SET @Idx=@Idx+1;
END;

/** Remove irrelevant records.*/
DELETE FROM #OtherEvents WHERE ReportStatus=0;

SELECT NULL;

