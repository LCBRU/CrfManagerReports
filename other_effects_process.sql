UPDATE #OtherEvents
SET
    Days=DATEDIFF(day,StartDate,EndDate),
    DayStartMinutes=DATEPART(hour,StartDate)*60 + DATEPART(minute,StartDate),
    DayEndMinutes=DATEPART(hour,EndDate)*60 + DATEPART(minute,EndDate);


/** Calculate the number of minutes in and out of core hours for single day events.*/
UPDATE #OtherEvents
SET
    MinutesInCoreHours = CASE
    WHEN (DATEPART(weekday,StartDate) IN (1,7)) OR (DayEndMinutes&lt;@DayStartMinutes) OR (DayStartMinutes&gt;@DayEndMinutes) THEN
        0
    ELSE
        DATEDIFF(
            minute,
            CASE
                WHEN @DayStartMinutes&gt;DayStartMinutes THEN
                DATEADD(minute,@DayStartMinutes-DayStartMinutes,StartDate)
                ELSE
                StartDate
                END,
            CASE
                WHEN @DayEndMinutes&lt;DayEndMinutes THEN
                DATEADD(minute,@DayEndMinutes-DayEndMinutes,EndDate)
                ELSE
                EndDate
                END
            )
    END,
    MinutesOutCoreHours = CASE
        WHEN DATEPART(weekday,StartDate) IN (1,7) THEN
        DayEndMinutes-DayStartMinutes
        WHEN @DayStartMinutes&gt;DayStartMinutes THEN
        CASE
        WHEN DayEndMinutes&lt;@DayStartMinutes THEN
            DayEndMinutes-DayStartMinutes
        ELSE
            @DayStartMinutes-DayStartMinutes
        END
        ELSE
        0
        END
        +
        CASE
        WHEN DATEPART(weekday,StartDate) IN (1,7) THEN
        0
        WHEN @DayEndMinutes&lt;DayEndMinutes THEN
        CASE
            WHEN DayStartMinutes&gt;@DayEndMinutes THEN
            DayEndMinutes-DayStartMinutes
            ELSE
            DayEndMinutes-@DayEndMinutes
            END
        ELSE
        0
        END
    WHERE (Days=0)

/** Calculate the number of whole days in and out of core hours for multi-day events.*/
UPDATE #OtherEvents
SET
    MinutesInCoreHours=(@DayEndMinutes-@DayStartMinutes)*CASE WHEN (DATEPART(weekday,StartDate)=7) AND Days&gt;7 THEN (Days) ELSE Days-1 END,
    MinutesOutCoreHours=(@MinutesInDay-@DayEndMinutes+@DayStartMinutes)*CASE WHEN (DATEPART(weekday,StartDate)=7) AND Days&gt;7 THEN Days ELSE Days-1 END
WHERE (Days&gt;1)


/** Calculate the start and end of multi day events including weekends */
UPDATE #OtherEvents
SET
    MinutesInCoreHours = MinutesInCoreHours + CASE
    WHEN (DATEPART(weekday,StartDate) IN (1,7)) THEN
        0
    WHEN @DayStartMinutes&gt;DayStartMinutes THEN
        @DayEndMinutes-@DayStartMinutes
    WHEN @DayEndMinutes&gt;=DayStartMinutes THEN
        @DayEndMinutes-DayStartMinutes
    ELSE
        0
    END
    +
    CASE
    WHEN (DATEPART(weekday,EndDate) IN (1,7)) THEN
        0
    WHEN @DayEndMinutes&lt;DayEndMinutes THEN
        @DayEndMinutes-@DayStartMinutes
    WHEN @DayStartMinutes&lt;DayEndMinutes THEN
        DayEndMinutes-@DayStartMinutes
    ELSE
        0
    END,
MinutesOutCoreHours = MinutesOutCoreHours + CASE
    WHEN (DATEPART(weekday,StartDate) IN (1,7)) THEN
    @MinutesInDay-DayStartMinutes
    WHEN @DayStartMinutes&gt;DayStartMinutes THEN
    @DayStartMinutes-DayStartMinutes+@MinutesInDay-@DayEndMinutes
    WHEN @DayEndMinutes&lt;=DayStartMinutes THEN
    @MinutesInDay-DayStartMinutes
    WHEN @DayEndMinutes&gt;DayStartMinutes THEN
    @MinutesInDay-@DayEndMinutes
    END +
    CASE
    WHEN (DATEPART(weekday,EndDate) IN (1,7)) THEN
    DayEndMinutes
    WHEN @DayEndMinutes&lt;DayEndMinutes THEN
    @DayStartMinutes+DayEndMinutes-@DayEndMinutes
    WHEN @DayStartMinutes&lt;DayEndMinutes THEN
    @DayStartMinutes
    ELSE
    DayEndMinutes
    END
WHERE (Days&gt;0);


/** Start Saturday or end Sunday - add day out core hours and remove day in-core hours*/
UPDATE #OtherEvents
SET
    MinutesOutCoreHours=MinutesOutCoreHours + (@DayEndMinutes-@DayStartMinutes),
    MinutesInCoreHours=MinutesInCoreHours - (@DayEndMinutes-@DayStartMinutes)
WHERE (Days&gt;1)
    AND (Days&lt;3)
    AND (DATEPART(weekday,StartDate)=7 OR DATEPART(weekday,EndDate)=1);


/** Add 2 days in-core hours to out-core hours for every weekend covered by the event */
UPDATE #OtherEvents
SET
    MinutesInCoreHours = MinutesInCoreHours-(
    (@DayEndMinutes-@DayStartMinutes) * (2) * (
        CASE WHEN DATEPART(year,EndDate)&lt;&gt;DATEPART(year,StartDate) THEN
        53
        ELSE DATEPART(week,EndDate) END
        -DATEPART(week,StartDate))
    ),
    MinutesOutCoreHours=MinutesOutCoreHours + (
    (@DayEndMinutes-@DayStartMinutes)*(2)*(
        CASE WHEN DATEPART(year,EndDate)&lt;&gt;DATEPART(year,StartDate) THEN
        53
        ELSE
        DATEPART(week,EndDate) END -DATEPART(week,StartDate)))
        WHERE (Days&gt;2)
        AND (DATEPART(week,StartDate)&lt;&gt;DATEPART(week,EndDate));

SELECT NULL;
