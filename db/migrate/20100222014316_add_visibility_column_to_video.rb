class AddVisibilityColumnToVideo < ActiveRecord::Migration
  def self.up
    add_column :videos, :visibility, :string
  end

  def self.down
    remove_column :videos, :visibility
  end
end
