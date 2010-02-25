# 视频管理和编码模型
class Video < ActiveRecord::Base
  
  named_scope :published, :conditions => {:visibility => 'published'}
  named_scope :unpublished, :conditions => {:visibility => 'unpublished'}
  named_scope :pending, :conditions => {:state => 'pending'}
  named_scope :audited, :conditions => {:state => 'audited'}
  named_scope :no_encoding, :conditions => {:state => 'no_encoding'}
  named_scope :queued_up, :conditions => {:state => 'queued_up'}
  named_scope :converting, :conditions => {:state => 'converting'}
  named_scope :converted, :conditions => {:state => 'converted'}
  named_scope :error, :conditions => {:state => 'error'}
  named_scope :canceled, :conditions => {:state => 'canceled'}
  named_scope :soft_deleted, :conditions => {:state => 'soft_deleted'}
  named_scope :being, lambda { |state|
    { :conditions => { :state => state } }
  }
  
  # acl9插件object模型
  acts_as_authorization_object
  
  acts_as_taggable

  has_one :tv
  has_many :replies, :class_name => 'VideoReply'
  belongs_to :user

  # # paperclip提供的附件管理功能
  has_attached_file :asset,
                    :styles => lambda { |attachment|
                    if attachment.instance.converting? # 视频编码时可传入参数
                      # 可以在这里扩展视频的recipe 和 profile，作为参数传进去
                      {:transcoded => '500x376', 
                       :watermark_path => RAILS_ROOT + '/public/images/video_watermark_logo.png'}
                    else # 其它状态只传尺寸来截图
                      {:tiny => '78x59#', :small => '156x117#',
                        :medium => '328x246#', :large => '500x376#'}
                    end
                    },
                    :url => '/:class/:id/:style.:content_type_extension',
                    :path => ':rails_root/assets/:id_partition/:style.:content_type_extension',
                    :default_url => '/images/rails.png',
                    # 该模型只处理视频文件，不再同时处理图片文件，未来根据视频文件的状态加入编码的processor
                    # :processors => lambda { |a| a.video? ? [ :video_thumbnail ] : [ :thumbnail ] }
                    # :processors => [ :video_thumbnail ]
                    # :processors => [ :video_encoding ]
                    :processors => lambda { |video|
                      # 新视频状态为padding，进入编码队列的视频状态为queued_up，只有进入编码队列才能用video_encoding编码
                      if video.converting?
                        [ :video_encoding ]
                      else
                        [ :video_thumbnail ]
                      end
                    }

  # 用state_mechine插件管理文件状态
  # state machine (see http://github.com/pluginaweek/state_machine/tree/master for details)
  state_machine :initial => :pending do
    # 视频编码完成后将视频状态改变为已编码
    after_transition :to => :queued_up, :do => lambda { |video| 
                                                video.queued_at = Time.now
                                                video.encode! }
    after_transition :to => :converted, :do => :set_new_filename
    after_transition :to => :canceled, :do => lambda{ |video| video.withdraw! }
    after_transition :to => :soft_deleted, :do => lambda{ |video| video.withdraw! }
    after_transition :to => :converted, :do => lambda{ |video| video.publish! }
    after_transition :to => :no_encoding, :do => lambda{ |video| video.publish! }
    
    event :audit       do transition :pending => :audited end
    event :queue       do transition :audited => :queued_up end
    event :no_encode   do transition all - :pending => :no_encoding end
    event :convert     do transition :queued_up => :converting end
    event :fore_encode do transition all - :pending =>  :converting end
    event :converted   do transition :converting => :converted end
    event :failure     do transition :converting => :error end
    event :resume      do transition [:error, :canceled, :soft_deleted] => :pending end
    event :cancel      do transition all - :canceled => :canceled end
    event :soft_delete do transition all - :soft_deleted => :soft_deleted end
    
  end

  state_machine :visibility, :initial => :unpublished do
    after_transition :to => :published, :do => :change_tv_visibility
    after_transition :to => :unpublished, :do => :change_tv_visibility
    event :publish   do transition all => :published end
    event :withdraw  do transition all => :unpublished end
  end

  # 视频编码信息
  attr_accessor :duration, :container, :width, :height, 
              :video_codec, :video_bitrate, :fps, 
              :audio_codec, :audio_sample_rate

  # 用新进程列队编码视频，编码后改变视频状态为已编码
  # 本方法意图当有视频进入编码队列时，新建一个进程作为编码队列来编码，且只维持一个编码队列。编码队列完成进程退出
  # TODO 可配置多个编码队列，配置是否进行CPU使用限制
  # TODO 可配置为后台守候进程来编码
  def encode!
    if Video.converting.empty? # 如果有视频处于编码中，什么都不做，确保只有一个编码进程
      if queued_video = Video.queued_up.first # 从队列里取先入视频编码
        start_encode_queue(queued_video)
      end
    end
  end
  
  # spawn a new process to handle conversion
  # spawn(:nice => 7) do # 1－19，数字越大子进程比父进程优先级越低
  def start_encode_queue(video)
    # 用thread来处理
    # spawn(:method => :thread) do    
    spawn do     
      # logger.info(`ps aux | grep ruby`)
      # logger.info("PID: #{Process.pid}")
      # debugger
      # 如果是linux系统，设置只用1个cpu编码
      LinuxScheduler.set_affinity(0) if RUBY_PLATFORM =~ /Linux/
      video.convert! # 从队列状态变为编码状态
      begin
        begun_at = Time.now
        video.asset.reprocess! # 用paperclip processor处理视频编码
        ended_at = Time.now
      rescue PaperclipError => e
        flash[:notice] = e
        video.failure! # 编码出错
      end        
      video.started_encoding_at = begun_at
      video.encoded_at = ended_at
      video.encoding_time = (ended_at - begun_at).to_i
      video.converted! # 编码结束
      video.save!  
      encoding # 递归再看看编码时是否有放到队列里的视频
    end #spawn process
  end
  
  # 用rvideo判断文件是否为有效视频文件
  def video?(path)
    # # 尚未保存时的临时文件
    # if !self.asset.queued_for_write.empty?
    #   path = self.asset.queued_for_write[:original].path
    # # 保存后的文件
    # elsif self.asset.path
    #   # Rails.logger.info "Reading metadata of video file--#{self.id}"
    #   id_partion = ("%09d" % self.id).scan(/\d{3}/).join("/")
    #   file_name = '/original' + File.extname(self.asset_file_name)
    #   path = Rails.root.to_s + '/assets/' + id_partion + file_name
    # else
    #   return false
    # end
    inspector = RVideo::Inspector.new(:file => path)
    if inspector.valid? && inspector.video?
      return true
    else
      return false
    end
  end
  
  def meta_info
    path=self.asset.path
    inspector = RVideo::Inspector.new(:file => path)
    if inspector.valid? && inspector.video?
      # raise FormatNotRecognised unless inspector.valid? and inspector.video?

      @duration = (inspector.duration rescue nil)
      @container = (inspector.container rescue nil)
      @width = (inspector.width rescue nil)
      @height = (inspector.height rescue nil)

      @video_codec = (inspector.video_codec rescue nil)
      @video_bitrate = (inspector.bitrate rescue nil)
      @fps = (inspector.fps rescue nil)

      @audio_codec = (inspector.audio_codec rescue nil)
      @audio_sample_rate = (inspector.audio_sample_rate rescue nil)

      # Don't allow videos with a duration of 0
      # raise FormatNotRecognised if self.duration == 0
    end
  end

  # 弃用
  # 用mime-type插件通过文件后缀判断的mime type来判断是否为视频文件
  # 如果 VIDEO_TYPE 里没有其mime type有问题，还是使用ffmpeg来判断是否为有效视频文件
  # def video?
  #   VIDEO_TYPE.include?(asset.content_type)
  # end

  # TODO 用该方法控制视频资源是否可下载，替换为acl9控制
  def downloadable?(user)
    true
  end

protected

  # This updates the stored filename with the video base file name
  def set_new_filename
    path=self.asset.path
    current_format = File.extname(path)
    basename       = File.basename(path, current_format)   
    update_attribute(:filename, basename)
  end
  
  def change_tv_visibility
    if t = self.tv 
      t.state = self.visibility
    end
  end

end
