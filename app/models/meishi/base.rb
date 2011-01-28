# 调用 meishi 数据库
class Meishi::Base < ActiveRecord::Base

  establish_connection( 
  :adapter  => CONFIG['meishi']["adapter"], 
  :host     => CONFIG['meishi']["host"], 
  :encoding => CONFIG['meishi']["encoding"], 
  :database => CONFIG['meishi']["database"], 
  :username => CONFIG['meishi']["username"], 
  :password => CONFIG['meishi']["password"])

end