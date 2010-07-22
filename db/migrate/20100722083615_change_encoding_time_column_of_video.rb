class ChangeEncodingTimeColumnOfVideo < ActiveRecord::Migration
  def self.up
    change_column :videos, :encoding_time, :string  
  end

  def self.down
    change_column :videos, :encoding_time, :time    
  end
end
