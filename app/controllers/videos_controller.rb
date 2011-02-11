class VideosController < ApplicationController
  
  before_filter :find_video, :only => [:show, :edit, :update, :destroy] # 必须在access_control之前取到@video
  
  # acl9插件提供的访问控制列表DSL
  access_control do
    allow all, :to => [:index, :show, :download]    
    allow :admin
    allow logged_in, :to => [:new, :create]
    allow :creator, :editor, :of => :video, :to => [:edit, :update] # :video 是对@video的引用
    # allow logged_in, :except => :destroy     
    # allow anonymous, :to => [:index, :show]
  end

  skip_before_filter :verify_authenticity_token, :only =>[:create]  # 供美食上传视频用

  def index
    @videos = Video.published.paginate :page => params[:page], :order => 'created_at DESC', :per_page => 12
  end

  def new
    flash[:notice] = "上传视频文件不能超过#{CONFIG['max_upload_file_size']}MB"
    @video = Video.new
    render('/meishi/videos/new_iframe', :layout => false) if params[:iframe] == "true"
    render('/meishi/videos/share_dv_iframe', :layout => false) if params[:iframe] == "share_dv"
    render('/meishi/videos/new_for_admin_iframe', :layout => false) if params[:iframe] == "for_admin"
  end

  def create   
    @video = Video.new(params[:video])
    @video.user = @current_user
    # flash上传的二进制流mime type是 application/octet-stream。
    # 需要给上传的视频文件用mime-type插件获取mime type保存到属性里
    # @video.asset_content_type = MIME::Types.type_for(@video.asset.original_filename).to_s
    @video.asset_content_type = File.mime_type?(@video.asset.original_filename)
    if @video.save
      tv_id = create_meishi_tv if params[:tv] # 直接操作meishi的tv模型
      if request.env['HTTP_USER_AGENT'] =~ /^(Adobe|Shockwave) Flash/
        # head(:ok, :id => @video.id) and return
        render :text => "id=#{@video.id} title=#{@video.title} desc=#{@video.description} tv_id=#{tv_id}"
      else
        # @video.convert
        flash[:notice] = '视频文件已成功上传'
        redirect_to @video
      end
    else
      render :action => 'new'
    end
  end

  def show
    @reply = VideoReply.new
  end

  # 下载文件，通过webserver的x sendfile直接发送文件
  # TODO 可在此完善下载计数器
  # TODO 下载的是原文件名的新文件
  # SEND_FILE_METHOD = 'default' # 配置webserver
  # SEND_FILE_METHOD = 'nginx' # 配置webserver为nginx，nginx需要相应配置X-Sendfile
  SEND_FILE_METHOD = CONFIG['web_server']
  def download
    head(:not_found) and return if (video = Video.find_by_id(params[:id])).nil?
    head(:forbidden) and return unless video.downloadable?(current_user)
    path = video.asset.path(params[:style])
    head(:bad_request) and return unless File.exist?(path) && params[:format].to_s == File.extname(path).gsub(/^\.+/, '')

    # cache-control
    head(:cache_control => "max-age=604800")
    
    send_file_options = { :type => File.mime_type?(path) }

    case SEND_FILE_METHOD
    when 'apache' then send_file_options[:x_sendfile] = true
    when 'nginx' then head(:x_accel_redirect => path.gsub(Rails.root, ''), :content_type => send_file_options[:type]) and return
    end

    send_file(path, send_file_options)
  end

private
 
  def find_video
    @video = Video.find(params[:id])
  end
  
  # 直接操作meishi的tv模型
  def create_meishi_tv
    tv              = Meishi::Tv.new
    tv.name         = @video.title
    tv.intro        = @video.description
    tv.state        = @video.visibility
    tv.flv_url      = @video.asset.path.gsub(RAILS_ROOT,'')
    tv.video_id     = @video.id
    tv.dv_type      = 2 # shadowgraph创建的视频类型。重要！meishi根据这个类型生成视频url。
    tv.is_published = 0
    tv.user_id      = params[:tv][:user_id]
    tv.article_category_id = params[:tv][:cat_id] if params[:tv][:cat_id]
    tv.save
    tv.located_in_all_city!
    return tv.id
  end

end
