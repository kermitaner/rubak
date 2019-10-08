#! /usr/bin/env ruby

#$VERBOSE=true

require 'zlib'    # for archive compression
require 'minitar' # for archive compression
require 'net/ftp' # for ftp upload
require 'timeout' # for ftp upload
require 'openssl' # for file encryption
require 'digest'

include Archive::Tar

# filename of config file
Kconfig='rubak.conf'
#openssl constant
MAGIC = 'Salted__'
#temp file for aes enrcyption
CRYPT_TMP='crypt.enc'

# file contains md5 hash and filesize of last built archive
FileMD5 = "rubak.md5"

#hash with default data , overwrite with data from config file
conf={
		server: nil, #address ftp server
		user: nil, 	#ftp user
		pass: nil,	#ftp pass
		port: 21,       #ftp port
		ftpDir: nil,	# path on ftp server for backup file
		exDirs: [],	#Directories to exclude
		exFiles: [],	#Files to exclude
		saveDirs: [],	#Directories to backup
		zipFiles: [],		#all files to zip & backup
		backupFile: 'BAK_', # default backupfile name
		backupSize: 0, 		# created filesize of archive(readonly)
    generations: 99,  #default 99 generations of backups
    passphrase: nil   # if set, archive will be aes-128-cbc encrypted by openssl
		}
    

# detect, if file has changed - different md5 hash or filesize
# or no stats file found
def check_change md5 , size

    if File.exists?(FileMD5)
      arr= IO.read(FileMD5).split(";")
      return false if  ( arr[0] == md5 && arr[1].to_i == size   ) 
    end
   # update stats file with new md5 hash & size
    IO.write(FileMD5, md5+";"+size.to_s)
    puts "md5 stats file updated"
    true # data changed
 end 
 
#get value following  keyword ( and space(s) )
def getVal(line)
  # value must not include space !!
  # eg. "-parm value"   -> match value only 
	return line.match(/(^.+[ ]+)([^ ]+)/)[2]
end

# zip all  files found into archive/tarball
# return md5 hash of source files
def make_tarball(destination, conf,curDir)
	Dir.chdir(curDir)
  md5=Digest::MD5.new  
  Zlib::GzipWriter.open(destination) do |gzip|
    out = Archive::Tar::Minitar::Output.new(gzip)
	 conf[:zipFiles].each { |f|	Archive::Tar::Minitar.pack_file(f, out) 
        md5.update IO.binread(f)
   }
    out.close
 end
 conf[:backupSize]=File.size(destination) #remember archive size
 return md5.hexdigest
end

#read data from config file into "conf" hash
def read_config(fi,conf,curDir)
	Dir.chdir curDir
	bDirs=bFiles=false
  
	IO.readlines(fi).each do |line|
		line.chomp!
    line.strip!
		next if line[0,1]=='#'  #comment line ?
		next if line.empty?         # ignore empty lines
		if line=~/^-exdirs/i
			bDirs,bFiles=true, false
		elsif line=~/^-exfiles/i
			bFiles,bDirs=true, false
		elsif line=~/^-server/i
			conf[:server]=getVal(line)
		elsif line=~/^-user/i
			conf[:user]=getVal(line)		
		elsif line=~/^-port/i
			conf[:port]=getVal(line).to_i
		elsif line=~/^-pass/i
			conf[:pass]=getVal(line)
		elsif line=~/^-ftpdir/i
			conf[:ftpDir]=getVal(line)
		elsif line=~/^-backupFile/i
			conf[:backupFile]=getVal(line)
         	  elsif line=~/^-generations/i
			conf[:generations]=getVal(line).to_i
      unless conf[:generations]>0
        puts 'error in config: generations must be > 0 !'
        puts line
        exit 1
      end
    elsif line=~/^-cryptpass/i
	conf[:passphrase]=getVal(line)
      	if conf[:passphrase].size<8
        	puts 'error in config: cryptpass minimum length is 8 chars !'
       	 	puts line
        	exit 1
       end
    elsif bDirs
			conf[:exDirs]<< line # collect directories to exclude/(nclude empty only)
    elsif bFiles
			conf[:exFiles]<< line # collect file masks to exclude
    else
			conf[:saveDirs]<< line # collect directories to backup
    end
  end
end

#find directories from config to backup
def findPaths (conf)
  puts aktTime()+' collecting files...'
  STDOUT.flush  #write out immediately
	conf[:saveDirs].each do |d|
		if File.directory?(d)
			Dir.chdir(d)
			getFiles(conf)
		else
			puts "\nWarning: Directory: \n"+d+" **not** found !"
		end
	end
end

#exclude file/directory  from backup ?
def exclude(f, ex)
	return false if ex.empty?
	ex.each { |d|		return true if File.fnmatch(d,File.basename(f) )}
	false
end

#recursively find all files/directories to backup
# and add to hash (:zipfiles) array
def getFiles (conf)
  # include even .xxx ( dotted ) files 
	(Dir.glob("*", File::FNM_DOTMATCH) - %w[. ..]).each do |f|
		f=File.expand_path(f)			# get complete path for file

		if File.directory?(f)
      conf[:zipFiles]<< f   #add even excluded dir as empty folder only
			next if exclude(f,conf[:exDirs])
			Dir.chdir(f)
			getFiles(conf)	# recursively explore subdir
			Dir.chdir("..")
		else
			conf[:zipFiles]<< f unless exclude(f,conf[:exFiles])
		end
	end
end

# log config values ( except ftp credentials / ssl pass phrase)
def logoutConfig(conf)
	if conf[:saveDirs].empty?
	puts "no Directories specified in #{Kconfig}"
	exit 1
end
puts 'backing up Directories:'
conf[:saveDirs].each { |e|	puts e}

unless conf[:exFiles].empty?
puts "\nexcluding all Files like:"
	conf[:exFiles].each { |e|  puts e}
end
unless conf[:exDirs].empty?
puts "\nexcluding all Directories like:"
	conf[:exDirs].each { |e|  puts e}
end
if conf[:server]
	print "\nupload to server: "+conf[:server]+":"+conf[:port].to_s
	puts '/'+conf[:ftpDir] if conf[:ftpDir]
        puts ""
end
if conf[:generations]
	puts "\keeping max #{conf[:generations]} generations "
end

end

# logout result :-)
def logoutResult(curDir,conf)
	puts "\n"+conf[:zipFiles].size.to_s+" Files written to: \n"
	if conf[:server]
		print conf[:server]+":"+conf[:port].to_s
		print '/'+conf[:ftpDir]+'/' if conf[:ftpDir]
	else
		print curDir+ '/'
   end
	puts FN_BACKUP
	puts "\nFilesize: "+(conf[:backupSize]/1024).to_s+' KB'
end

# simple (binary ) file upload
def upload(file,conf)
ftp_server = conf[:server]
user       = conf[:user]
pass       = conf[:pass]
fport       = conf[:port]
con_timeout      = 30
transfer_timeout = 600

ftp = nil
begin
  Timeout.timeout( con_timeout ) do
    ftp = Net::FTP.new(  )
    ftp.connect(ftp_server, port=fport)
    ftp.login( user, pass )
  end
	puts "\n"+aktTime()+" uploading file: "+file
  STDOUT.flush  #write out immediately
  Timeout.timeout( transfer_timeout ) do
	  ftp.chdir(conf[:ftpDir]) if conf[:ftpDir]
    ftp.putbinaryfile( file )
    puts aktTime()+" upload finished"
     ftpCleanUp(conf,ftp) if conf[:generations]
  end

rescue
  STDERR.puts "Error ftp-transfer server: #{ftp_server}"
  raise
ensure
  ftp.close if ftp
  GC.start
  sleep 3
end

end

# delete oldest archive ( until config limit is reached )
def ftpCleanUp(conf,ftp)
    limit=conf[:generations]
  puts "Remote backup files:"
  #must match generated archive names
  a=ftp.nlst(conf[:backupFile]+'????????-??????.tgz').sort	
  a.each do |e| puts e end
  return if a.size<= limit
  while (a.size> limit)
     ftp.delete(a[0])
      puts 'Deleted old archive: '+a[0]
      a.delete_at(0)
  end
end

#generate archive name 
def genArchivename(conf)
# generate filename for backup (tarball ) file
# important for sort order !!  in cleanup method !!
s=Time.now.strftime("%Y%m%d-%H%M%S") 	#gen timestamp for file extension
#(e.g.: BAK_20140805-140205.tgz)
return conf[:backupFile]+s+'.tgz'
end

#delete oldest archive
def cleanUp(conf)
  limit=conf[:generations]
  return unless limit
  #must match generated archive names
  a=Dir[conf[:backupFile]+'????????-??????.tgz'].sort  
  a.each do |e| puts e end
  return if a.size<= limit
  while (a.size> limit)
      File.delete(a[0])
      puts 'Deleted old archive: '+a[0]
      a.delete_at(0)
  end
end
#format current time as string
def aktTime()
  (Time.now).strftime("%T")
end

# encrypt file with openssl aes-128-cbc method
# decrypt with:
# openssl enc -d -aes-128-cbc -k password -in infile -out outfile
# ( from example found in ruby forum :-)
def encryptFile(fileIn,conf)

salt_len = 8
buf=''
password = conf[:passphrase]
cipher = 'aes-128-cbc'
puts aktTime()+' encrypting archive...'
STDOUT.flush  #write out immediately
salt= OpenSSL::Random::pseudo_bytes(salt_len)

c = OpenSSL::Cipher::Cipher.new(cipher)
c.encrypt
#generate key + IV from given password
c.pkcs5_keyivgen(password, salt, 1)
File.open(CRYPT_TMP,'wb') do |fo|
  
  fo.write(MAGIC) #write magic string 
  fo.write(salt)      #write 8 bytes random salt
  File.open(fileIn,'rb') do |fi|
    while fi.read(4096,buf)  
      fo.write c.update(buf)
    end
    fo.write( c.final)
  end
end

#overwrite archive with crypted archive
puts aktTime()+' archive encrypted '
File.rename(CRYPT_TMP,fileIn)
end

##############################
#++++++  start of script ++++++++++++
##############################
t0=Time.now
puts 'Start: '+ t0.to_s
curDir=File.expand_path(File.dirname(__FILE__)) # save current working dir

read_config(Kconfig,conf,curDir)		# read config data from file into hash
FN_BACKUP=genArchivename(conf)

logoutConfig(conf)					# log config data
findPaths(conf)						# collect all directories/files

m5 = make_tarball(FN_BACKUP,conf,curDir)		# create  archive

if check_change m5 ,  conf[:backupSize]  # has md5 checksum/size changed ?
  puts "Data changed"
  encryptFile(FN_BACKUP,conf) if conf[:passphrase] # encrypt archive
  upload(FN_BACKUP,conf)	if conf[:server]		#upload backup archive

  cleanUp(conf) unless conf[:server] # cleanup local archives unless ftp upload requested
  logoutResult(curDir,conf)
else
  puts "no changes detected"
end
	File.delete(FN_BACKUP)
	puts 'deleted local file: '+FN_BACKUP
puts aktTime()+' finished, runtime: '+ (Time.now-t0).to_s+' sec'
