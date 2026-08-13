class PreventCategoryCycles < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      CREATE OR REPLACE FUNCTION crystell.prevent_category_cycle()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF NEW.parent_id IS NULL THEN
          RETURN NEW;
        END IF;

        IF NEW.parent_id = NEW.id THEN
          RAISE EXCEPTION 'category cannot be its own parent';
        END IF;

        IF EXISTS (
          WITH RECURSIVE ancestors AS (
            SELECT id, parent_id
            FROM categories
            WHERE id = NEW.parent_id
              AND tenant_id = NEW.tenant_id
              AND store_id = NEW.store_id

            UNION ALL

            SELECT category.id, category.parent_id
            FROM categories category
            JOIN ancestors ancestor ON category.id = ancestor.parent_id
            WHERE category.tenant_id = NEW.tenant_id
              AND category.store_id = NEW.store_id
          )
          SELECT 1
          FROM ancestors
          WHERE id = NEW.id
        ) THEN
          RAISE EXCEPTION 'category hierarchy cycle detected';
        END IF;

        RETURN NEW;
      END;
      $$
    SQL

    execute <<~SQL
      CREATE TRIGGER categories_prevent_cycle
      BEFORE INSERT OR UPDATE OF parent_id, tenant_id, store_id
      ON categories
      FOR EACH ROW
      EXECUTE FUNCTION crystell.prevent_category_cycle()
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS categories_prevent_cycle ON categories"
    execute "DROP FUNCTION IF EXISTS crystell.prevent_category_cycle()"
  end
end
