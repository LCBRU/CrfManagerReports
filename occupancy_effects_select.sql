SELECT
    @SectionIdx=1,
    @SectionStartDate=@StartDate,
    @SectionEndDate=DATEADD(month,1,@StartDate),
    @TotalSections=DATEDIFF(month,@StartDate,@EndDate);

CREATE TABLE #OccupancyEvents
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
    INSERT INTO #OccupancyEvents (SectionIndex,SectionStartDate,SectionEndDate,ResourceID,OwnerID,ResourceName,StartDate,EndDate)
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
    INNER JOIN @OccupancyStatus OS ON VRE.REStatusID=OS.StatusID
    WHERE (
        (@SpecialisedOnly=0 AND NOT EXISTS(SELECT 1 FROM @SpecialisedEvents WHERE SpecResourceID=VRE.ResourceID AND TEndDate&gt;=SpecStartDate AND TStartDate&lt;SpecEndDate))
        OR
        (@SpecialisedOnly=1 AND EXISTS(SELECT 1 FROM @SpecialisedEvents WHERE SpecResourceID=VRE.ResourceID AND TEndDate&gt;=SpecStartDate AND TStartDate&lt;SpecEndDate))
    )
    AND (VRE.REAreaID=301)
    AND (
        ((TStartDate&gt;=@SectionStartDate) AND (TStartDate&lt;@SectionEndDate))
        OR((TEndDate&gt;@SectionStartDate) AND (TEndDate&lt;=@SectionEndDate) ))
    ORDER BY TStartDate;


    /** Truncate events overlapping the range to be within the range. Events crossing more than one range will
    be sub-divided accordingly */
    UPDATE #OccupancyEvents
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
UPDATE #OccupancyEvents
SET DateLabel = CONVERT(VARCHAR(10),StartDate,103)


/** Calculate core hours */
/** Combine overlapping events into single event.*/
DECLARE @Overlaps TABLE
(
    Idx INT NOT NULL UNIQUE,
    ResourceID UNIQUEIDENTIFIER NOT NULL,
    StartDate DATETIME NOT NULL,
    EndDate DATETIME NOT NULL
)

SELECT @Idx=1, @Count=COUNT(1)
FROM #OccupancyEvents;

WHILE (@Idx&lt;=@Count)
BEGIN
    SET @ResourceID=NULL;

    SELECT
        @ResourceID=ResourceID,
        @EventStartDate=StartDate,
        @EventEndDate=EndDate
    FROM #OccupancyEvents
    WHERE (Idx=@Idx)
    AND (ReportStatus=1);

    IF (@ResourceID IS NOT NULL)
    BEGIN
        INSERT INTO @Overlaps(Idx,ResourceID,StartDate,EndDate)
        SELECT
            Idx,
            ResourceID,
            StartDate,
            EndDate
    FROM #OccupancyEvents
    WHERE (ReportStatus=1)
        AND (ResourceID=@ResourceID)
        AND (EndDate&gt;@EventStartDate)
        AND (StartDate&lt;@EventEndDate);

    IF EXISTS(SELECT * FROM @Overlaps HAVING COUNT(*)&gt;0)
    BEGIN
        UPDATE #OccupancyEvents
        SET ReportStatus=0
        WHERE Idx IN (SELECT Idx FROM @Overlaps);

        INSERT INTO #OccupancyEvents (SectionIndex,SectionStartDate,SectionEndDate,ResourceID,OwnerID,ResourceName,StartDate,EndDate)
        SELECT
            SectionIndex,
            SectionStartDate,
            SectionEndDate,
            ResourceID,
            OwnerID,
            ResourceName,
            (SELECT MIN(StartDate) FROM @Overlaps),
            (SELECT MAX(EndDate) FROM @Overlaps)
        FROM #OccupancyEvents
        WHERE (Idx=@Idx);

    END;

        DELETE FROM @Overlaps;
    END

    SET @Idx=@Idx+1;
END;

/** Remove irrelevant records.*/
DELETE FROM #OccupancyEvents WHERE ReportStatus=0;

SELECT NULL;
