#! /usr/bin/env ruby

#$VERBOSE=true

require 'zlib'    # for archive compression
require 'minitar' # for archive compression
require 'net/ftp' # for ftp upload
require 'timeout' # for ftp upload
require 'openssl' # for file encryption
require 'digest' # for md5 hash
require 'time'
#require 'FileUtils' # for file copy

# filename of config file
p ARGV
unless ARGV[0]
  puts "error: missing config file parameter:"
  puts "example: (ruby) rubak.rb .rubak.conf "
  exit 1
end

Kconfig=ARGV[0]
#openssl constant
MAGIC = 'Salted__'
#temp file for aes enrcyption
CRYPT_TMP='crypt.enc'


#hash with default data , overwrite with data from config file
conf={
		server: nil, #address ftp server
		user: nil, 	#ftp user
		pass: nil,	#ftp pass
		port: 21,       #ftp port
 		modTS: Time.new(0),	#lates modification timestamp

		ftpDir: nil,	# path on ftp server for backup file
		exDirs: [],	#Directories to exclude
		exFiles: [],	#Files to exclude
		saveDirs: [],	#Directories to backup
		zipFiles: [],		#all files to zip & backup
		backupFile: 'BAK_', # default backupfile name
    backupdDrive: nil, # drive and path where to save backup
		backupSize: 0, 		# created filesize of archive(readonly)
    fsize: 0 , # sum of file size sourcefiles
    generations: 99,  #default 99 generations of backups
    passphrase: nil   # if set, archive will be aes-128-cbc encrypted by openssl
		}
    
#check if size or timestamp changed
def check_change (conf, curDir)
  Dir.chdir curDir
  return true unless File.exist?(FileStats)
  arr = IO.read(FileStats).split(",")
  return true if arr[0].to_i != conf[:fsize]
  return true if conf[:modTS ].to_i  > Time.parse(arr[1]).to_i 
  false
end
#get value following  keyword ( and space(s) )
def getVal(line)
  # value must not include space !!
  # eg. "-parm value"   -> match value only 
	return line.match(/(^.+[ ]+)([^ ]+)/)[2]
end

# zip all  files found into archive/tarball
def make_tarball(destination, conf,curDir)
	Dir.chdir(curDir)

  gzip = Zlib::GzipWriter.new(File.open(destination, 'wb'))
  tar = Minitar::Output.new(gzip)
	 conf[:zipFiles].each { |f|	Minitar.pack_file(f, tar)    }
  tar.close

 conf[:backupSize]=File.size(destination) #remember archive size
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
 		elsif line=~/^-backupDrive/i
			conf[:backupDrive]=getVal(line)

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
    ts = File.mtime(f)
		if File.directory?(f)
      conf[:fsize] += 1 #count dirs as size 1
      conf[:zipFiles]<< f   #add even excluded dir as empty folder only
			next if exclude(f,conf[:exDirs])
      conf[:modTS] = ts if ts > conf[:modTS]
			Dir.chdir(f)
			getFiles(conf)	# recursively explore subdir
			Dir.chdir("..")
		else
      next if exclude(f,conf[:exFiles])
			conf[:zipFiles]<< f 
      conf[:fsize] += File.size(f)
      conf[:modTS] = ts if ts > conf[:modTS]

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

# copy backup file to drive
def backup2Drive(src,conf)
  dest = conf[:backupDrive]
  dest = dest + "/" unless dest [-1] =~ /[\/\\]/
  dest = dest + src
  puts src
  puts dest
  FileUtils.mkdir_p(File.dirname(dest))
  FileUtils.cp(src, dest)
  puts aktTime()+" archive copied"
  cleanUp(conf) if conf[:generations]
  
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
  a=[]
  Dir.chdir conf[:backupDrive] do
    #must match generated archive names
    a=Dir[conf[:backupFile]+'????????-??????.tgz'].sort  
  end
    a.each do |e| puts e end
    return if a.size<= limit
    Dir.chdir conf[:backupDrive] do
      while (a.size> limit)
        File.delete(a[0])
        puts 'Deleted old archive: '+a[0]
        a.delete_at(0)
      end
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

# file contains last filesize + latest update timestamp
FileStats = conf[:backupFile]+".stats"

findPaths(conf)						# collect all directories/files

if check_change( conf, curDir) 
  make_tarball(FN_BACKUP,conf,curDir)		# create  archive
  puts "Data changed"
  encryptFile(FN_BACKUP,conf) if conf[:passphrase] # encrypt archive
  upload(FN_BACKUP,conf)	if conf[:server]		#upload backup archive
  backup2Drive(FN_BACKUP,conf)	if conf[:backupDrive]		#upload backup archive
  logoutResult(curDir,conf)
  IO.write(FileStats, conf[:fsize].to_s+","+conf[:modTS].to_s ) # write stats file only on success
  puts "stats file updated"
  	File.delete(FN_BACKUP)
	puts 'deleted local file: '+FN_BACKUP
else 
  puts "no changes detected"
end
puts aktTime()+' finished, runtime: '+ (Time.now-t0).to_s+' sec'
