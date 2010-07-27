# 调用meishi tv模型
class Meishi::Tv < Meishi::Base


  set_table_name 'enjoyoung_production.tvs'
  # set_primary_key "id"
  
  belongs_to :video

  # Tv的状态可以完全拷贝video的状态，作到一致避免麻烦。所以不自己用状态机变迁状态。
  # # 用state_mechine插件管理文件状态
  # # state machine (see http://github.com/pluginaweek/state_machine/tree/master for details)
  # state_machine :initial => :pending do
  #   # 视频编码完成后将视频状态改变为已编码
  #   after_transition :to => :converted, :do => :publish
  #   event :audit       do transition :pending => :audited end
  #   event :queue       do transition :audited => :queued_up end
  #   event :convert     do transition :queued_up => :converting end
  #   event :converted   do transition :converting => :converted end
  #   event :failure     do transition :converting => :error end
  #   event :resume      do transition [:error, :canceled, :soft_deleted] => :pending end
  #   event :cancel      do transition all - :canceled => :canceled end
  #   event :soft_delete do transition all - :soft_deleted => :soft_deleted end
  # end
  
  def located_in_all_city!
    Meishi::Coordinate.create(:location_pseud_id => "all",
                              :location_type     => "City",
                              :locatee_type      => "Tv",
                              :locatee_id        => self.id)
  end

end