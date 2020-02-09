# Backup RSYNC Scripts
My rsync backup scripts

Recently I had a external 8T USB drive fail (which Seagate kindly replaced under guarantee),
so I thought I'd make am attempt at getting my Ubuntu 19.10 desktop backed up properly.

My goal was to run the following scripts on a hourly crontab:-
- run my /home/user
- run my /root
- everything in /etc
- everything in /var/www
- everything in /var/lib/mysql - ie my mariadb backup
- some method of ensuring all were backed up just before shutdown

On Shutdown
In spite of a lot of searching and experimention, I have not acheived a successful hook
into systemd. So instead I've added symbolic links in /usr/local/bin with the names of poweroff and 
shutown to conveniently overrule the underlying commands - I usually shutdown on the command-line. But
not restart as I'm assuming that I'll need to operate quickly.
(to be added later)
However, I may want to shutdown just as the crontab jobs are running. Thus I needed to ensure
my scripts were not re-entrant, and my shutdown script needs to wait for the crontabs to finish - I can
launch shutdown and go to bed, knowing my PC will shutdown eventually.

I may have been over the top, but it's been fun writing and testing!

Feb 2020

