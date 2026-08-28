"""
Retira sp_search_travels, que es codigo muerto ya que al final no se utiliza
"""
from django.db import migrations

# El DROP es exactamente el backward_sql de la migracion 0002
DROP = """
DROP FUNCTION IF EXISTS public.sp_search_travels(double precision, double precision, double precision, double precision, double precision, double precision, timestamp without time zone, timestamp without time zone);
"""

# Y el reverse, su forward_sql
RECREATE = """
CREATE OR REPLACE FUNCTION public.sp_search_travels(
    p_orig_lat double precision, p_orig_lng double precision, p_rad_orig double precision,
    p_dest_lat double precision, p_dest_lng double precision, p_rad_dest double precision,
    p_date_from timestamp without time zone, p_date_until timestamp without time zone
)
RETURNS TABLE (
    id_travel uuid,
    dist_origin float8,
    dist_dest float8
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        t.id_travel,
        ST_Distance(
            t.origin_point::geography,
            ST_SetSRID(ST_MakePoint(p_orig_lng, p_orig_lat), 4326)::geography
        ) AS dist_origin,
        ST_Distance(
            t.destination_point::geography,
            ST_SetSRID(ST_MakePoint(p_dest_lng, p_dest_lat), 4326)::geography
        ) AS dist_dest
    FROM travel t
    WHERE
        (p_rad_orig = 0 OR ST_DWithin(
            t.origin_point::geography,
            ST_SetSRID(ST_MakePoint(p_orig_lng, p_orig_lat), 4326)::geography,
            p_rad_orig * 1000
        ))
        AND
        (p_rad_dest = 0 OR ST_DWithin(
            t.destination_point::geography,
            ST_SetSRID(ST_MakePoint(p_dest_lng, p_dest_lat), 4326)::geography,
            p_rad_dest * 1000
        ))
        AND (p_date_from IS NULL OR t.travel_date >= p_date_from)
        AND (p_date_until IS NULL OR t.travel_date <= p_date_until)
        AND t.state = 'active';
END;
$$;
"""


class Migration(migrations.Migration):

    dependencies = [
        ('travels', '0012_seed_catalog'),
    ]

    operations = [
        migrations.RunSQL(DROP, reverse_sql=RECREATE),
    ]
