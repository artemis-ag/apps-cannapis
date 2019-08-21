class CreateIntegrations < ActiveRecord::Migration[6.0]
  def change
    create_table :integrations, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true
      t.integer :facility_id
      t.string :state
      t.string :vendor
      t.string :vendor_id
      t.string :key
      t.string :secret
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :integrations, :id, unique: true
    add_index :integrations, :facility_id
  end
end