WITH
__dumped AS (
    SELECT {{ if (it.columns && it.columns.length > 0) { }}
        {{= it.columns }},
    {{ } }}
    {{= it.geomColumn }},
    (st_dump(ST_MakeValid({{= it.geomColumn }}))).geom __dumped_geometry
    FROM ({{= it.layerSql }}) AS __cdb_query
),
__simplified_geometries AS (
    SELECT
    {{ if (it.columns && it.columns.length > 0) { }}
        {{= it.columns }},
    {{ } }}
    {{= it.geomColumn }},
    __dumped_geometry,
    ST_Simplify(
        {{?it.removeRepeatedPoints}}ST_RemoveRepeatedPoints({{?}}
            {{= it.clipFn }}(
                __dumped_geometry,
                ST_Expand(
                    ST_MakeEnvelope({{= it.extent.xmin }}, {{= it.extent.ymin }}, {{= it.extent.xmax }}, {{= it.extent.ymax }}, {{= it.srid }}),
                    {{= it.xyzResolution }} * {{= it.bufferSize}}
                )
            ){{?it.removeRepeatedPoints}},
            {{= it.xyzResolution }} * {{= it.removeRepeatedPointsTolerance}}
        ){{?}},
        {{= it.xyzResolution }} * {{= it.simplifyDpRatio}}
    ) __the_geometry
    FROM __dumped
    WHERE (
        ST_Intersects(
            __dumped_geometry,
            ST_Expand(
                ST_MakeEnvelope({{= it.extent.xmin }}, {{= it.extent.ymin }}, {{= it.extent.xmax }}, {{= it.extent.ymax }}, {{= it.srid }}),
                {{= it.xyzResolution }} * {{= it.bufferSize}}
            )
        )
    )
),
__collected_geometries AS (
    SELECT {{ if (it.columns && it.columns.length > 0) { }}
        {{= it.columns }},
    {{ } }}
    CASE WHEN ST_NPoints({{= it.geomColumn }}) > 1
        THEN
        ST_Collect(
            CASE WHEN ST_IsEmpty(__the_geometry) OR __the_geometry IS NULL
                THEN ST_Envelope({{= it.geomColumn }})
                ELSE __the_geometry
            END
        )
        ELSE
            ST_GeometryN(
                ST_Collect(
                    CASE WHEN ST_IsEmpty(__the_geometry) OR __the_geometry IS NULL
                        THEN ST_Envelope({{= it.geomColumn }})
                        ELSE __the_geometry
                    END
                ),
                1
            )
    END AS __the_geometry
    FROM __simplified_geometries
    GROUP BY {{ if (it.columns && it.columns.length > 0) { }}
        {{= it.columns }},
    {{ } }}
    {{= it.geomColumn }}
)
SELECT row_to_json(featurecollection) as geojson
FROM (
    SELECT 'FeatureCollection' AS TYPE,
        array_to_json(array_agg(feature)) AS features
        FROM (
            SELECT 'Feature' AS TYPE,
            ST_AsGeoJSON(__the_geometry)::json AS geometry,
            {{ if (!it.columns || it.columns.length === 0) { }}
                '{}'::json
            {{ } else { }}
                row_to_json((SELECT l FROM (SELECT {{= it.columns }}) AS l))
            {{ } }} AS properties
            FROM __collected_geometries
        ) AS feature
) AS featurecollection;
