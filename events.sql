CREATE PROC get_periods_from_appointments AS

CREATE TABLE _app_working (
	id INT NOT NULL,
	resource_id NVARCHAR(50) NOT NULL,
	start_date_time DATETIME2(7) NOT NULL,
	end_date_time DATETIME2(7) NOT NULL,
	merged_min_id INT NOT NULL,
);

CREATE INDEX _idx_app_working ON _app_working(resource_id, merged_min_id, start_date_time);

INSERT INTO _app_working (id, resource_id, start_date_time, end_date_time, merged_min_id)
SELECT id, resource_id, start_date_time, end_date_time, id
FROM appointments
;


CREATE TABLE _to_update (
	id INT NOT NULL,
	merged_min_id INT NOT NULL
);

DECLARE @todo INT;
SET @todo = 1


WHILE (@todo > 0)
BEGIN
	TRUNCATE TABLE _to_update;


	INSERT INTO _to_update (id, merged_min_id)
	SELECT a2.id, a1.merged_min_id
	FROM _app_working a1
	JOIN _app_working a2
		ON a2.resource_id = a1.resource_id
		AND a2.start_date_time <= a1.end_date_time
		AND a2.end_date_time >= a1.start_date_time
		AND a2.merged_min_id > a1.merged_min_id
	;


	UPDATE a
	SET a.merged_min_id = u.merged_min_id
	FROM _app_working a
	JOIN _to_update u
		ON u.id = a.id
	;

	SELECT @todo = COUNT(*)
	FROM _to_update;

END

TRUNCATE TABLE occupied_periods;

INSERT INTO occupied_periods (merged_min_id, resource_id, [start_date_time], [end_date_time], [start_date], [end_date], records_mrged)
SELECT
	merged_min_id AS id,
	resource_id,
	MIN(start_date_time) AS start_date_time,
	MAX(end_date_time) AS end_date_time,
	CONVERT(DATE, MIN(start_date_time)) AS start_date,
	CONVERT(DATE, MAX(end_date_time)) AS end_date,
	COUNT(*)
FROM _app_working
GROUP BY resource_id, merged_min_id
;

DROP TABLE _to_update;
DROP TABLE _app_working;
