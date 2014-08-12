rubak
=====

 configurable ruby script to backup directories as zipped archives to ftp server (wth. exclude dirs / files option)<br/>
 read rubak.conf for configuration options<br/>
 intended to be run as cron job on server to backup directories to remote ftp server<br/>
 generations limit config  option (default 10) to limit number  of existing backups locally/ on ftp server <br/>
 
 further enhancements planned:  <br/>
 -add option to AES encrypt archive before upload, <br/>
 -accept optional parameter as name for config.file<br/>
 
 pre production status, use on own risk !!
 
 eg. for crontab entry ( edit with crontab -e on server ): 
 <br>
 <pre> 0 */8 * * * /usr/local/script/rubak.rb >> /var/log/rubak.log 2>&1</pre>
 
 =execute rubak.rb every 8 hours and append sysout messages to /var/log/rubak.log
 (advice: add rubak.log to logrotate script, to prevent log overflow :) 
