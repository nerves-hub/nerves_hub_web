defmodule NervesHub.Repo.Migrations.AddPrereleaseSupportToSemverMatch do
  use Ecto.Migration

  def change do
    # First create a helper function to compare pre-release identifiers
    execute """
    CREATE OR REPLACE FUNCTION compare_prerelease_ids(id1 text, id2 text) RETURNS int
    LANGUAGE plpgsql
    IMMUTABLE
    AS $$
    DECLARE
      is_num1 boolean;
      is_num2 boolean;
      num1 int;
      num2 int;
    BEGIN
      -- Check if identifiers are numeric (all digits)
      is_num1 := id1 ~ '^[0-9]+$';
      is_num2 := id2 ~ '^[0-9]+$';

      -- Both numeric: compare numerically
      IF is_num1 AND is_num2 THEN
        num1 := id1::int;
        num2 := id2::int;
        IF num1 < num2 THEN RETURN -1;
        ELSIF num1 > num2 THEN RETURN 1;
        ELSE RETURN 0;
        END IF;
      END IF;

      -- Numeric always lower precedence than non-numeric
      IF is_num1 AND NOT is_num2 THEN RETURN -1; END IF;
      IF NOT is_num1 AND is_num2 THEN RETURN 1; END IF;

      -- Both non-numeric: compare lexically
      IF id1 < id2 THEN RETURN -1;
      ELSIF id1 > id2 THEN RETURN 1;
      ELSE RETURN 0;
      END IF;
    END;
    $$;
    """, "DROP FUNCTION IF EXISTS compare_prerelease_ids;"

    # Now create the helper to compare pre-release versions
    execute """
    CREATE OR REPLACE FUNCTION compare_prerelease(pre1 text, pre2 text) RETURNS int
    LANGUAGE plpgsql
    IMMUTABLE
    AS $$
    DECLARE
      ids1 text[];
      ids2 text[];
      len1 int;
      len2 int;
      min_len int;
      i int;
      cmp int;
    BEGIN
      -- Empty pre-release means higher precedence (release version)
      IF pre1 IS NULL OR pre1 = '' THEN
        IF pre2 IS NULL OR pre2 = '' THEN RETURN 0;
        ELSE RETURN 1; -- release > pre-release
        END IF;
      END IF;

      IF pre2 IS NULL OR pre2 = '' THEN RETURN -1; END IF; -- pre-release < release

      -- Split on dots
      ids1 := string_to_array(pre1, '.');
      ids2 := string_to_array(pre2, '.');
      len1 := array_length(ids1, 1);
      len2 := array_length(ids2, 1);
      min_len := LEAST(len1, len2);

      -- Compare each identifier
      FOR i IN 1..min_len LOOP
        cmp := compare_prerelease_ids(ids1[i], ids2[i]);
        IF cmp != 0 THEN RETURN cmp; END IF;
      END LOOP;

      -- All equal so far, longer set has higher precedence
      IF len1 < len2 THEN RETURN -1;
      ELSIF len1 > len2 THEN RETURN 1;
      ELSE RETURN 0;
      END IF;
    END;
    $$;
    """, "DROP FUNCTION IF EXISTS compare_prerelease;"

    # Now update semver_match to use pre-release comparison
    execute """
    CREATE OR REPLACE FUNCTION semver_match(version text, req text) RETURNS boolean
    LANGUAGE plpgsql
    IMMUTABLE
    RETURNS NULL ON NULL INPUT
    AS $$
    DECLARE
      ver_parts text[];
      ver_base text;
      ver_pre text;
      req_parts text[];
      req_base text;
      req_pre text;
      ver_base_arr int[];
      req_base_arr int[];
      upper_bound int[];
      base_cmp int;
      pre_cmp int;
    BEGIN
      -- Split version into base and pre-release
      ver_parts := string_to_array(version, '-');
      ver_base := ver_parts[1];
      ver_pre := CASE WHEN array_length(ver_parts, 1) > 1 THEN array_to_string(ver_parts[2:array_length(ver_parts, 1)], '-') ELSE NULL END;

      ver_base_arr := string_to_array(ver_base, '.')::int[];

      -- Handle different operators
      CASE
        WHEN req LIKE '~>%' THEN
          req_base := substring(req from 4);
          req_base_arr := string_to_array(req_base, '.')::int[];

          -- Calculate upper bound
          upper_bound := CASE
            WHEN array_length(req_base_arr, 1) = 1 THEN
              ARRAY[req_base_arr[1] + 1, 0]
            ELSE
              array_append(
                req_base_arr[1:(array_length(req_base_arr, 1) - 2)],
                req_base_arr[array_length(req_base_arr, 1) - 1] + 1
              ) || ARRAY[0]
          END;

          RETURN ver_base_arr >= req_base_arr AND ver_base_arr < upper_bound;

        WHEN req LIKE '>=%' THEN
          req_base := substring(req from 4);
          req_parts := string_to_array(req_base, '-');
          req_base_arr := string_to_array(req_parts[1], '.')::int[];
          req_pre := CASE WHEN array_length(req_parts, 1) > 1 THEN array_to_string(req_parts[2:array_length(req_parts, 1)], '-') ELSE NULL END;

          -- Compare base versions
          IF ver_base_arr > req_base_arr THEN RETURN true;
          ELSIF ver_base_arr < req_base_arr THEN RETURN false;
          ELSE
            -- Base versions equal, compare pre-release
            pre_cmp := compare_prerelease(ver_pre, req_pre);
            RETURN pre_cmp >= 0;
          END IF;

        WHEN req LIKE '<=%' THEN
          req_base := substring(req from 4);
          req_parts := string_to_array(req_base, '-');
          req_base_arr := string_to_array(req_parts[1], '.')::int[];
          req_pre := CASE WHEN array_length(req_parts, 1) > 1 THEN array_to_string(req_parts[2:array_length(req_parts, 1)], '-') ELSE NULL END;

          IF ver_base_arr < req_base_arr THEN RETURN true;
          ELSIF ver_base_arr > req_base_arr THEN RETURN false;
          ELSE
            pre_cmp := compare_prerelease(ver_pre, req_pre);
            RETURN pre_cmp <= 0;
          END IF;

        WHEN req LIKE '>%' THEN
          req_base := substring(req from 3);
          req_parts := string_to_array(req_base, '-');
          req_base_arr := string_to_array(req_parts[1], '.')::int[];
          req_pre := CASE WHEN array_length(req_parts, 1) > 1 THEN array_to_string(req_parts[2:array_length(req_parts, 1)], '-') ELSE NULL END;

          IF ver_base_arr > req_base_arr THEN RETURN true;
          ELSIF ver_base_arr < req_base_arr THEN RETURN false;
          ELSE
            pre_cmp := compare_prerelease(ver_pre, req_pre);
            RETURN pre_cmp > 0;
          END IF;

        WHEN req LIKE '<%' THEN
          req_base := substring(req from 3);
          req_parts := string_to_array(req_base, '-');
          req_base_arr := string_to_array(req_parts[1], '.')::int[];
          req_pre := CASE WHEN array_length(req_parts, 1) > 1 THEN array_to_string(req_parts[2:array_length(req_parts, 1)], '-') ELSE NULL END;

          IF ver_base_arr < req_base_arr THEN RETURN true;
          ELSIF ver_base_arr > req_base_arr THEN RETURN false;
          ELSE
            pre_cmp := compare_prerelease(ver_pre, req_pre);
            RETURN pre_cmp < 0;
          END IF;

        WHEN req LIKE '=%' THEN
          req_base := substring(req from 3);
          req_parts := string_to_array(req_base, '-');
          req_base_arr := string_to_array(req_parts[1], '.')::int[];
          req_pre := CASE WHEN array_length(req_parts, 1) > 1 THEN array_to_string(req_parts[2:array_length(req_parts, 1)], '-') ELSE NULL END;

          -- For =, match base version prefix and exact pre-release
          IF (ver_base_arr[1:array_length(req_base_arr, 1)] = req_base_arr) THEN
            -- If req has pre-release, version must have matching pre-release
            IF req_pre IS NOT NULL THEN
              IF ver_pre IS NULL THEN
                RETURN false; -- req has pre-release but version doesn't
              ELSE
                RETURN ver_pre = req_pre;
              END IF;
            ELSE
              -- No pre-release in req, just match base
              RETURN true;
            END IF;
          ELSE
            RETURN false;
          END IF;

        ELSE
          RETURN NULL;
      END CASE;
    END;
    $$;
    """, """
    CREATE OR REPLACE FUNCTION semver_match(version text, req text) RETURNS boolean
    LANGUAGE SQL
    IMMUTABLE
    RETURNS NULL ON NULL INPUT
    AS $$
    SELECT CASE
    WHEN version LIKE '%-%' THEN 'f'
    WHEN req LIKE '~>%' THEN
        string_to_array(version, '.')::int[] >= string_to_array(substring(req from 4), '.')::int[]
        AND
        string_to_array(version, '.')::int[] <
        CASE
          WHEN array_length(string_to_array(substring(req from 4), '.'), 1) = 1 THEN
            ARRAY[(string_to_array(substring(req from 4), '.')::int[])[1] + 1, 0]
          ELSE
            array_append(
              (string_to_array(substring(req from 4), '.')::int[])[1:(array_length(string_to_array(substring(req from 4), '.'), 1) - 2)],
              (string_to_array(substring(req from 4), '.')::int[])[array_length(string_to_array(substring(req from 4), '.'), 1) - 1] + 1
            ) || ARRAY[0]
        END
    WHEN req LIKE '>=%' THEN string_to_array(version, '.')::int[] >= string_to_array(substring(req from 4), '.')::int[]
    WHEN req LIKE '<=%' THEN string_to_array(version, '.')::int[] <= string_to_array(substring(req from 4), '.')::int[]
    WHEN req LIKE '>%' THEN string_to_array(version, '.')::int[] > string_to_array(substring(req from 3), '.')::int[]
    WHEN req LIKE '<%' THEN string_to_array(version, '.')::int[] < string_to_array(substring(req from 3), '.')::int[]
    WHEN req LIKE '=%' THEN
        (string_to_array(version, '.')::int[])[1:array_length(string_to_array(substring(req from 3), '.'), 1)] =
        string_to_array(substring(req from 3), '.')::int[]
    ELSE NULL
    END $$;
    """
  end
end
