rubak
=====

 configurable ruby script to backup directories as zipped archives to ftp server (wth. exclude dirs / files option)
 read rubak.conf for configuration options
 intended to be run as cron job on server to backup directories to remote ftp server
 
 further enhancements planned:  
 -add generation counter option to limit number  of existing backups on ftp server ( round robin)
 -add option to AES encrypt archive before upload, 
 -accept optional parameter as name for config.file
 
 pre production status, use on own risk !!
 
 eg. for crontab entry ( edit with crontab -e on server ):
 0 */8 * * * /usr/local/script/rubak.rb >> /var/log/rubak.log 2>&1
 
 =execute rubak.rb every 8 hours and append sysout messages to /var/log/rubak.log
 (advice: add rubak.log to logrotate script, to prevent log overflow :) 
