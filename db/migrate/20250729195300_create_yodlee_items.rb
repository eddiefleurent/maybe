class CreateYodleeItems < ActiveRecord::Migration[7.2]
  def change
    create_table :yodlee_items, id: :uuid do |t|
      t.string :name, null: false
      t.text :user_session, null: false
      t.string :yodlee_id
      t.string :institution_id
      t.string :institution_url
      t.string :institution_color
      t.text :available_products, array: true, default: []
      t.jsonb :raw_payload
      t.jsonb :raw_institution_payload
      t.string :status, default: "good", null: false
      t.references :family, type: :uuid, null: false, foreign_key: true, index: true
      t.boolean :scheduled_for_deletion, default: false, null: false
      t.datetime :last_synced_at

      t.timestamps
    end

    create_table :yodlee_accounts, id: :uuid do |t|
      t.string :yodlee_id, null: false
      t.references :yodlee_item, type: :uuid, null: false, foreign_key: true, index: true
      t.references :account, type: :uuid, foreign_key: true, index: true
      t.jsonb :raw_payload
      t.datetime :last_synced_at

      t.timestamps

      t.index [:yodlee_id, :yodlee_item_id], unique: true
    end
  end
end
