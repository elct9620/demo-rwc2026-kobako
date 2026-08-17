class CreateEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :entries do |t|
      t.string :source, null: false
      t.string :external_id, null: false

      # Only what all three sources genuinely carry is required. A Facebook post
      # has no title, and a post that is only a photo has no text either, so a
      # column a source cannot fill stays empty rather than being invented.
      t.string :title
      t.text :summary
      t.string :url, null: false
      t.string :thumbnail_url
      t.datetime :published_at, null: false

      # Whatever one source has and the others do not, kept as it arrived.
      t.json :metadata, default: {}

      t.timestamps

      # The unique index is what makes a daily fetch idempotent: rows already
      # here are skipped rather than compared.
      t.index [ :source, :external_id ], unique: true
      # Reading is one query across all three sources, ordered by this.
      t.index :published_at
    end
  end
end
