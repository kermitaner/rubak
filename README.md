rubak
=====

 configurable ruby script to backup directories as zipped archives to ftp server (wth. exclude dirs / files option)<br/>
 read rubak.conf for configuration options<br/>
 ( needs ruby interpreter ( >= 2.0 ) and some gems  to be installed )
 intended to be run as cron job on server to backup directories to remote ftp server or local backup drive<br/>
 generations limit config  option (default 10) to limit number  of existing backups locally/ on ftp server <br/>
 option to AES encrypt archive before upload <br/>
 <b>make sure to remember password from conf file !! or Data will be lost !!</b><br/>
 decrypt with openssl command line tool : <br/>
 <pre>openssl enc -d -aes-128-cbc -k password -in infile -out outfile</pre>
 
 <b>make sure, you can decrypt your backup correctly before using encryption !!</b>
 
 further enhancements planned:  <br/>

 -accept optional parameter as name for config.file<br/>
 
 pre production status, use at own risk !!
 
 eg. for crontab entry ( edit with crontab -e on linux server ): 
 <br>
 <pre> 0 */8 * * * /usr/local/script/rubak.rb >> /var/log/rubak.log 2>&1</pre>
 
 =execute rubak.rb every 8 hours and append sysout messages to /var/log/rubak.log
 (advice: add rubak.log to logrotate script, to prevent log overflow :) 
