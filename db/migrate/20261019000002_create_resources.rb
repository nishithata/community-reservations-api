class CreateResources < ActiveRecord::Migration[8.1]
  def change
    create_table :resources do |t|
      t.string :name, null: false
      t.text :description
      t.string :category, null: false
      t.string :location
      t.integer :capacity
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :resources, :name, unique: true
    add_index :resources, [ :active, :category ]
    add_check_constraint :resources, "category IN ('room', 'equipment', 'space', 'vehicle')",
      name: "resources_category_allowed"
    add_check_constraint :resources, "capacity IS NULL OR capacity > 0", name: "resources_capacity_positive"
  end
end
