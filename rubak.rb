#! /usr/bin/env ruby

#$VERBOSE=true

require 'zlib'
require 'archive/tar/minitar'
require 'net/ftp'
require 'timeout'
include Archive::Tar

# filename config file
Kconfig='rubak.conf'

#hash with default data , overwrite with data from config file
conf={
		server: nil, #address ftp server
		user: nil, 	#ftp user
		pass: nil,	#ftp pass
		ftpDir: nil,	# path on ftp server for backup file
		exDirs: [],	#Directories to exclude
		exFiles: [],	#Files to exclude
		saveDirs: [],	#Directories to backup
		zipFiles: [],		#all files to zip & backup
		backupFile: 'BAK_', # default backupfile name
		backupSize: 0, 		# created filesize of archive(readonly)
    generations: 99  #default 99 generations of backups
		}

#get value following  keyword ( and space(s) )
def getVal(line)
	return line.match(/(^.+[ ]+)([^ ]+)/)[2]
end

# zip all  files found into archive/tarball
def make_tarball(destination, conf,curDir)
	Dir.chdir(curDir)
  Zlib::GzipWriter.open(destination) do |gzip|
    out = Archive::Tar::Minitar::Output.new(gzip)
	 conf[:zipFiles].each { |f|	Archive::Tar::Minitar.pack_file(f, out) }
    out.close
 end
 conf[:backupSize]=File.size(destination) #remember archive size
end

#read data from config file into "conf" hash
def read_config(fi,conf,curDir)
	Dir.chdir curDir
	bDirs=bFiles=false
	IO.readlines(fi).each do |line|
		line.chomp!
    line.strip!
		next if line[0,1]=='#'	#comment line ?
		next if line.empty?
		if line=~/^-exdirs/i
			bDirs=true
			bFiles=false
		elsif line=~/^-exfiles/i
			bFiles=true
			bDirs=false
		elsif line=~/^-server/i
			conf[:server]=getVal(line)
		elsif line=~/^-user/i
			conf[:user]=getVal(line)
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
		elsif bDirs
			conf[:exDirs]<< line
		elsif	bFiles
			conf[:exFiles]<< line
		else
			conf[:saveDirs]<< line
		end
	end
end

def findPaths (conf)
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
def getFiles (conf)
	(Dir.glob("*", File::FNM_DOTMATCH) - %w[. ..]).each do |f|
		f=File.expand_path(f)			# get complete path for file

		if File.directory?(f)
			#add excluded dir as empty folder only
			conf[:zipFiles]<< f
			next if exclude(f,conf[:exDirs])
			Dir.chdir(f)
			getFiles(conf)	# explore subdir
			Dir.chdir("..")
		else
			conf[:zipFiles]<< f unless exclude(f,conf[:exFiles])
		end
	end
end

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
	print "\nupload to server: "+conf[:server]
	puts '/'+conf[:ftpDir] if conf[:ftpDir]
end
if conf[:generations]
	puts "\keeping max #{conf[:generations]} generations "
end
STDOUT.flush
end

def logoutResult(curDir,conf)
	puts "\n"+conf[:zipFiles].size.to_s+" Files written to: \n"
	if conf[:server]
		print conf[:server]
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

con_timeout      = 30
transfer_timeout = 600

ftp = nil
begin
  timeout( con_timeout ) do
    ftp = Net::FTP.new( ftp_server )
    ftp.login( user, pass )
  end
	puts "\nuploading file: "+file
  timeout( transfer_timeout ) do
	  ftp.chdir(conf[:ftpDir])
    ftp.putbinaryfile( file )
     ftpCleanUp(conf,ftp) if conf[:generations]
  end
		puts "upload finished"
rescue
  STDERR.puts "Error ftp-transfer server: #{ftp_server}"
  raise
ensure
  ftp.close if ftp
  GC.start
  sleep 3
end
	File.delete(file)
	puts 'deleted local file: '+file
end
def ftpCleanUp(conf,ftp)
    limit=conf[:generations]
  #must match generated archive names
  a=ftp.nlst(conf[:backupFile]+'????????-??????.tgz')
  a.each do |e| puts e end
  return if a.size<= limit
  while (a.size> limit)
     ftp.delete(a[0])
      puts 'Deleted old archive: '+a[0]
      a.delete_at(0)
  end
end

def genArchivename(conf)
	# generate filename for backup (tarball ) file
s=Time.now.strftime("%Y%m%d-%H%M%S") 	#gen timestamp for file extension
#(e.g.: BAK_20140805-140205.tgz)
return conf[:backupFile]+s+'.tgz'
end
def cleanUp(conf)
  limit=conf[:generations]
  return unless limit
  #must match generated archive names
  a=Dir[conf[:backupFile]+'????????-??????.tgz']  
  a.each do |e| puts e end
  return if a.size<= limit
  while (a.size> limit)
      File.delete(a[0])
      puts 'Deleted old archive: '+a[0]
      a.delete_at(0)
  end
end
#++++++  start script ++++++++++++
t0=Time.now
puts 'Start: '+ t0.to_s
curDir=File.expand_path(File.dirname(__FILE__)) # save current working dir

read_config(Kconfig,conf,curDir)		# read config data from file into hash
FN_BACKUP=genArchivename(conf)

logoutConfig(conf)					# log config data
findPaths(conf)						# collect all directories/files

make_tarball(FN_BACKUP,conf,curDir)		# create  archive

upload(FN_BACKUP,conf)	if conf[:server]		#upload backup archive
cleanUp(conf) unless conf[:server]
logoutResult(curDir,conf)
puts 'finished, runtime: '+ (Time.now-t0).to_s+' sec'