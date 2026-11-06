class AddPositionScoreToBooks < ActiveRecord::Migration[8.0]
  def up
    add_column :books, :position_score, :float

    execute <<~SQL
      UPDATE books
      SET position_score = ordered.row_number
      FROM (
        SELECT id, row_number() over (order by title, id) AS row_number
        FROM books
      ) AS ordered
      WHERE books.id = ordered.id
    SQL

    change_column_null :books, :position_score, false
    add_index :books, [ :position_score, :id ]
  end

  def down
    remove_index :books, [ :position_score, :id ]
    remove_column :books, :position_score
  end
end
