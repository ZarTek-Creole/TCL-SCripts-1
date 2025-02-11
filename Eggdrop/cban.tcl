##########
# KickBan TCL
##########
# This script is highly experimental and needs eggdrop 1.9
# curently the default branch at https://github.com/eggheads/eggdrop
#
# In order for this script to work, you need to enable some features, especially:
#
# https://github.com/eggheads/eggdrop/blob/develop/eggdrop.conf#L1122
# should be set to: set cap-request "account-notify extended-join"
#
# https://github.com/eggheads/eggdrop/blob/develop/eggdrop.conf#L1379
# should be set to: set use-354 1
#
# USE AT YOUR OWN RISK! YOU HAVE BEEN WARNED!
##########

##########
# Changelog
##########
# 20/06/2020
# -= v1 =-
# - Initial release
##########
# 28/06/2020
# -= v2 =-
# - Converted the script into a namespace
# - Added temporary ban command, default ban reason and ban duration (for temp ban)
##########
# 28/06/2020
# -= v2.1 =-
# - Added some bot protections
##########
# 10/02/2021
# -= v2.2 =-
# - Removed unused vars
# - Code cleanup
# - Syntax fixing
#
# -= v2.3 =-
# - Added the possibility to remotely add/remove/check bans
##########
# 19/02/2021
# -= v2.4 =-
# - Added kick command (also remote kick)
# - Added PM commands to help keep anonymity
# - Fixed logic within procedures to be more resilient
# - More code cleanup
##########

##########
# COMMANDS
##########
# - NOTE: the #chan variable is optional only on public commands and if not specified defaults to the channel
# - where the command is being issued
#
##########
# Public commands
########## 
# - @cban [#chan] <nick> - bans the nick in the format *!*user@host (nick needs to be in the channel)
#
# - @tban [#chan] <nick> - Adds a temporary ban in the specified nick (nick must be on channel) with the duration
#   specified on banDuration variable
#
# - @addban [#chan] <mask> - Adds the specified mask to the bot ban list (this doesn't do any sanity checks, so you can end up banning everyone)
#
# - @kick [#chan] <nick> - Kicks someone from the channel
#
# - @uncban [#chan] <mask> - Removes the specified mask
#
# - @bans [#chan] - Sends a PM to the user showing the current internal ban list for the channel
#
##########
# PM commands
##########
# - cban <chan> <nick> - bans the nick in the format *!*user@host (nick needs to be in the channel)
#
# - uncban <#chan> <mask> - Removes the specified mask
#
# - bans <#chan> - Sends a PM to the user showing the current internal ban list for the channel
#
# - addban <#chan> <mask> - Adds the specified mask to the bot ban list (this doesn't do any sanity checks, so you can end up banning everyone)
#
# - tban <#chan> <nick> - Adds a temporary ban in the specified nick (nick must be on channel) with the duration
#   specified on banDuration variable
#
# - kick <#chan> <nick> - Kicks someone from the specified channel
#
##########
# END OF COMMANDS
##########
namespace eval cban {

	##########
	# CONFIGURATION
	##########
	# Trigger for the command
	variable banTrigger "@"

	# Default ban reason
	variable banReason "User has has been banned from the channel!"
	
	# Default kick reason
	variable kickReason "Your behaviour is not conducive for the desired environment!"

	# How many minutes for the temp ban
	variable banDuration "2"
	
	# Revenge kick reason when someone tries to ban the bot (%s will be replaced by the nick of
	# the person that tried to ban the bot)
	variable revengeBan "\002\00304Revenge Ban#\003\002 You wish %s! Next time, try to ban \00305yourself\003!"
	
	# Revenge kick reason when someone tries to kick the bot (%s will be replaced by the nick that
	# tried to kick the bot)
	variable revengeKick "\002\00304Revenge Kick#\003\002 You wish %s! Next time, try to kick \00305yourself\003!"

	##########
	# END OF CONFIGURATION
	##########

	###############
	# DON'T TOUCH ANYTHING BELOW UNLESS YOU KNOW WHAT YOU ARE DOING
	###############
	# If you touch the code below and then complain the script "suddenly stopped working" I'll touch you at night. (THANKS thommey)
	###############

	proc getBanTriga {} {
		variable ::cban::banTrigger
		return $::cban::banTrigger
	}
	
	##########
	# Public binds
	##########
	bind pub - ${banTrigger}cban ::cban::cban:pub
	bind pub - ${banTrigger}uncban ::cban::uncban:pub
	bind pub - ${banTrigger}addban ::cban::addban:pub
	bind pub - ${banTrigger}tban ::cban::tban:pub
	bind pub - ${banTrigger}kick ::cban::kick:pub
	bind pub - ${banTrigger}bans ::cban::bans:pub
	
	##########
	# PM binds
	##########
	bind msg - cban ::cban::cban:msg
	bind msg - uncban ::cban::uncban:msg
	bind msg - addban ::cban::addban:msg
	bind msg - tban ::cban::tban:msg
	bind msg - kick ::cban::kick:msg
	bind msg - bans ::cban::bans:msg
	
	##########
	# Public procs
	##########
	
	# @cban
	proc cban:pub {nick uhost hand chan text} {
		global botnick
		variable revengeBan
		variable banReason
		variable tchan "[lindex [split $text] 0]"
		variable bantype "[channel get $tchan ban-type]"
		
		if {![matchstr "#*" $tchan]} {
			variable tchan "$chan"
			variable target "[lindex [split $text] 0]"
		} else {
			variable target "[lindex [split $text] 1]"
		}
		
		variable banmask "[maskhost ${target}![getchanhost $target $tchan] $bantype]"

		if {![isidentified $nick]} {
			putserv "PRIVMSG $chan :ERROR! You need to be identified to use this command."
			return 0
		}
		
		if {![botonchan $tchan] || [channel get $tchan inactive]} {
			putserv "PRIVMSG $chan :ERROR! I'm not on $tchan or $tchan is set as inactive."
			return 0
		}
		
		if {![botisop $tchan]} {
			putserv "PRIVMSG $chan :ERROR! I'm not OP on $tchan"
			return 0
		}
		
		if {![isop $nick $tchan]} {
			putserv "PRIVMSG $chan :ERROR! You need to be OP on $tchan to use this command."
			return 0
		}

		if {$target eq ""} {
			putserv "PRIVMSG $chan :ERROR! Syntax: [::cban::getBanTriga]cban \[#chan\] <nick>"
			return 0
		}

		if {![onchan $target $tchan]} {
			putserv "PRIVMSG $chan :ERROR! $target needs to be on $tchan"
			return 0
		}
		
		if {($target eq $botnick && $tchan eq $chan)} {
			putkick $tchan $nick [format $revengeBan $nick]
			return 0
		} else {
			putserv "PRIVMSG $chan :[format $revengeBan $nick]"
			return 0
		}

		putkick $tchan $target $banReason
		pushmode $tchan +b $banmask
		newchanban "$tchan" "$banmask" "$nick" "$banReason" 0
		putserv "PRIVMSG $chan :Added $banmask to $tchan ban list."
		return 0
	}

	
	# @tban
	proc tban:pub {nick uhost hand chan text} {
		global botnick
		variable banReason
		variable revengeBan
		variable tchan "[lindex [split $text] 0]"
		variable bantype "[channel get $chan ban-type]"
		
		if {![matchstr "#*" $tchan]} {
			variable tchan "$chan"
			variable target "[lindex [split $text] 0]"
		} else {
			variable target "[lindex [split $text] 1]"
		}
		
		variable banmask "[maskhost ${target}![getchanhost $target $tchan] $bantype]"

		if {![isidentified $nick]} {
			putserv "PRIVMSG $chan :ERROR! You need to be identified to use this command."
			return 0
		}
		
		if {![botonchan $tchan] || [channel get $tchan inactive]} {
			putserv "PRIVMSG $chan :ERROR! I'm not on $tchan or $tchan is set as inactive."
			return 0
		}
		
		if {![botisop $tchan]} {
			putserv "PRIVMSG $chan :ERROR! I'm not OP on $tchan"
			return 0
		}

		if {![isop $nick $tchan]} {
			putserv "PRIVMSG $chan :ERROR! You need to be OP on $tchan to use this command."
			return 0
		}

		if {$target eq ""} {
			putserv "PRIVMSG $chan :ERROR! Syntax: [::cban::getBanTriga]tban \[#chan\] <nick>"
			return 0
		}
		
		if {![onchan $target $tchan]} {
			putserv "PRIVMSG $chan :ERROR! $target needs to be on $tchan"
			return 0
		}
		
		if {($target eq $botnick && $tchan eq $chan)} {
			putkick $tchan $nick [format $revengeBan $nick]
			return 0
		} else {
			putserv "PRIVMSG $chan :[format $revengeBan $nick]"
			return 0
		}

		putkick $tchan $target $banReason
		pushmode $tchan +b $banmask
		newchanban "$tchan" "$banmask" "$nick" "$banReason" $::cban::banDuration
		putserv "PRIVMSG $chan :Temporarily banned $banmask on $tchan"
		return 0
	}
	
	# @addban
	proc addban:pub {nick uhost hand chan text} {
		global botnick botname
		variable revengeBan
		variable banReason
		variable tchan "[lindex [split $text] 0]"
		
		if {![matchstr "#*" $tchan]} {
			variable tchan "$chan"
			variable banmask "[lindex [split $text] 0]"
		} else {
			variable banmask "[lindex [split $text] 1]"
		}
		
		

		if {![isidentified $nick]} {
			putserv "PRIVMSG $chan :ERROR! You need to be identified to use this command."
			return 0
		}
		
		if {![botonchan $tchan] || [channel get $chan inactive]} {
			putserv "PRIVMSG $chan :ERROR! I'm not on $tchan or $tchan is set as inactive."
			return 0
		}
		
		if {![botisop $tchan]} {
			putserv "PRIVMSG $chan :ERROR! I'm not OP on $tchan"
			return 0
		}
		
		if {![isop $nick $tchan]} {
			putserv "PRIVMSG $chan :ERROR! You need to have at least OP to use this command."
			return 0
			}
		
		if {$banmask eq ""} {
			putserv "PRIVMSG $chan :ERROR! Syntax: [::cban::getBanTriga]addban \[#chan\] <mask>"
			return 0
		}

		if {$banmask eq "*!*@*"} {
			putserv "PRIVMSG $chan :ERROR! That mask is too broad and therefore is denied"
			return 0
		}
		
		if {([matchstr $banmask $botname] && $tchan eq $chan)} {
			putkick $tchan $nick [format $revengeBan $nick]
			return 0
		} else {
			putserv "PRIVMSG $chan :[format $revengeBan $nick]"
			return 0
		}
		
		pushmode $tchan +b $banmask
		newchanban "$tchan" "$banmask" "$nick" "$banReason" 0
		putserv "PRIVMSG $chan :Added $banmask to $tchan ban list."
		return 0
	}
	
	# @kick
	proc kick:pub {nick uhost hand chan text} {
		global botnick
		variable kickReason
		variable revengeKick
		variable tchan "[lindex [split $text] 0]"
		
		if {![matchstr "#*" $tchan]} {
			variable tchan "$chan"
			variable target "[lindex [split $text] 0]"
		} else {
			variable target "[lindex [split $text] 1]"
		}
		
		if {![isidentified $nick]} {
			putserv "PRIVMSG $chan :ERROR! You need to be identified to use this command."
			return 0
		}
		
		if {![botonchan $tchan] || [channel get $tchan inactive]} {
			putserv "PRIVMSG $chan :ERROR! I'm not on $tchan or $tchan is set as inactive."
			return 0
		}
		
		if {![botisop $tchan]} {
			putserv "PRIVMSG $chan :ERROR! I'm not OP on $tchan"
			return 0
		}
		
		if {![isop $nick $tchan]} {
			putserv "PRIVMSG $chan :ERROR! You need to be OP on $tchan to use this command."
			return 0
		}
		
		if {$target eq ""} {
			putserv "PRIVMSG $chan :ERROR! Syntax: [::cban::getBanTriga]kick \[#chan\] <nick>"
			return 0
		}
		
		if {($target eq $botnick && $tchan eq $chan)} {
			putkick $tchan $nick [format $revengeKick $nick]
			return 0
		} else {
			putserv "PRIVMSG $chan :[format $revengeKick $nick]"
			return 0
		}
		
		putkick $tchan $target $kickReason
		return 0
	}
	
	# @uncban
	proc uncban:pub {nick uhost hand chan text} {
		global botnick
		
		variable tchan "[lindex [split $text] 0]"
		
		if {![matchstr "#*" $tchan]} {
			variable tchan "$chan"
			variable unbanmask "[lindex [split $text] 0]"
		} else {
			variable unbanmask "[lindex [split $text] 1]"
		}

		if {![isidentified $nick]} {
			putserv "PRIVMSG $chan :ERROR! You need to be identified to use this command."
			return 0
		}
		
		if {![botonchan $tchan] || [channel get $tchan inactive]} {
			putserv "PRIVMSG $chan :ERROR! I'm not on $tchan or $tchan is set as inactive."
			return 0
		}
		
		if {![botisop $tchan]} {
			putserv "PRIVMSG $chan :ERROR! I'm not OP on $tchan"
			return 0
		}

		if {![isop $nick $tchan]} {
			putserv "PRIVMSG $chan :ERROR! You need to be OP on $tchan to use this command."
			return 0
			}
		
		if {$unbanmask eq ""} {
			putserv "PRIVMSG $chan :ERROR! Syntax: [::cban::getBanTriga]uncban \[#chan\] <mask>. Use [::cban::getBanTriga]bans \[#chan\]to see the channel ban list."
			return 0
		}

		if {![isban $unbanmask $tchan]} {
			putserv "PRIVMSG $chan :ERROR! $unbanmask does not exist in my database."
			return 0
		}

		killchanban "$tchan" "$unbanmask"
		pushmode $tchan -b $unbanmask
		putserv "PRIVMSG $chan :$unbanmask removed from the ban list for $tchan"
		return 0
	}
	
	# @bans
	proc bans:pub {nick uhost hand chan text} {
		global botnick
		
		variable tchan "[lindex [split $text] 0]"
		
		if {![matchstr "#*" $tchan]} {
			variable tchan "$chan"
		}

		if {![isidentified $nick]} {
			putserv "PRIVMSG $chan :ERROR! $nick, you need to be identified to use this command."
			return 0
		}
		
		if {![botonchan $tchan] || [channel get $tchan inactive]} {
			putserv "PRIVMSG $chan :ERROR! I'm not on $tchan or $tchan is set as inactive."
			return 0
		}

		if {![isop $nick $tchan]} {
			putserv "PRIVMSG $chan :ERROR! $nick, you need to have at least OP on $tchan to use this command."
			return 0
		}
				
		if {[banlist $tchan] eq ""} {
			putserv "PRIVMSG $chan :There are no bans on $tchan"
			return 0
		}

		putquick "PRIVMSG $chan :BANLIST for $tchan sent to $nick"

		foreach botban [banlist $tchan] {
			variable banmask "[lindex [split $botban] 0]"
			variable creator "[lindex [split $botban] end]"
			putserv "PRIVMSG $nick :\002BanMask:\002 $banmask - \002Creator:\002 $creator"
		}
		return 0
	}
	
	##########
	# PM procs
	##########
	
	# cban
	proc cban:msg {nick uhost hand text} {
		global botnick
		variable revengeBan
		variable banReason
		variable chan "[lindex [split $text] 0]"
		variable target "[lindex [split $text] 1]"
		variable bantype "[channel get $chan ban-type]"
		variable banmask "[maskhost ${target}![getchanhost $target $chan] $bantype]"
		
		if {![isidentified $nick]} {
			putserv "PRIVMSG $nick :You need to be identified to use this command."
			return 0
		}
		
		if {![matchstr "#*" $chan]} {
			putserv "PRIVMSG $nick :ERROR! Syntax: cban <#chan> <nick>"
			return 0
		}
		
		if {![botonchan $chan] || [channel get $chan inactive]} {
			putserv "PRIVMSG $nick :ERROR! I'm not on $chan or $chan is set as inactive."
			return 0
		}
		
		if {![botisop $chan]} {
			putserv "PRIVMSG $nick :ERROR! I'm not OP on $chan"
			return 0
		}
		
		if {![isop $nick $chan]} {
			putserv "PRIVMSG $nick :ERROR! You need to be OP on $chan to use this command"
			return 0
		}
		
		if {$target eq ""} {
			putserv "PRIVMSG $nick :ERROR! Syntax: cban <#chan> <nick>"
			return 0
		}
		
		if {![onchan $target $chan]} {
			putserv "PRIVMSG $nick :ERROR! $target needs to be on $chan"
			return 0
		}
		
		if {$target eq $botnick} {
			putkick $chan $nick [format $revengeBan $nick]
			return 0
		}
		
		putkick $chan $target $banReason
		pushmode $chan +b $banmask
		newchanban "$chan" "$banmask" "$nick" "$banReason" 0
		putserv "PRIVMSG $nick :$banmask added to $chan ban list.ac"
		return 0
	}
	
	# tban
	proc tban:msg {nick uhost hand text} {
		global botnick
		variable banReason
		variable revengeBan
		variable banDuration
		variable chan "[lindex [split $text] 0]"
		variable target "[lindex [split $text] 1]"
		variable bantype "[channel get $chan ban-type]"
		variable banmask "[maskhost ${target}![getchanhost $target $chan] $bantype]"
		
		if {![isidentified $nick]} {
			putserv "PRIVMSG $nick :ERROR! You need to be identified to use this command."
			return 0
		}
		
		if {![matchstr "#*" $chan]} {
			putserv "PRIVMSG $nick :ERROR! Syntax: tban <#chan> <nick>"
			return 0
		}
		
		if {![botonchan $chan] || [channel get $chan inactive]} {
			putserv "PRIVMSG $nick :ERROR! I'm not on $chan or $chan is set as inactive."
			return 0
		}
		
		if {![botisop $chan]} {
			putserv "PRIVMSG $nick :ERROR! I'm not OP on $chan"
			return 0
		}
		
		if {![isop $nick $chan]} {
			putserv "PRIVMSG $nick :ERROR! You need to be OP on $chan to use this command"
			return 0
		}
		
		if {$target eq ""} {
			putserv "PRIVMSG $nick :ERROR! Syntax: tban <#chan> <nick>"
			return 0
		}
		
		if {![onchan $target $chan]} {
			putserv "PRIVMSG $nick :ERROR! $target needs to be on $chan"
			return 0
		}
		
		if {$target eq $botnick} {
			putkick $chan $nick [format $revengeBan $nick]
			return 0
		}
		
		putkick $chan $target $banReason
		pushmode $chan +b $banmask
		newchanban "$chan" "$banmask" "$nick" "$banReason" $banDuration
		putserv "PRIVMSG $nick :Added $banmask to $chan ban list."
		return 0
	}
	
	# addban
	proc addban:msg {nick uhost hand text} {
		global botname
		variable banReason
		variable revengeBan
		variable chan "[lindex [split $text] 0]"
		variable banmask "[lindex [split $text] 1]"
		
		if {![isidentified $nick]} {
			putserv "PRIVMSG $nick :ERROR! Ypu need to be identified to use this command."
			return 0
		}
		
		if {![matchstr "#*" $chan]} {
			putserv "PRIVMSG $nick :ERROR! Syntax: addban <#chan> <banmask>"
			return 0
		}
		
		if {![botonchan $chan] || [channel get $chan inactive]} {
			putserv "PRIVMSG $nick :ERROR! I'm not on $chan or $chan is set as inactive."
			return 0
		}
		
		if {![isop $nick $chan]} {
			putserv "PRIVMSG $nick :ERROR! You need to be OP on $chan to use this command."
			return 0
		}
		
		if {![botisop $chan]} {
			putserv "PRIVMSG $nick :ERROR! I'm not OP on $chan"
			return 0
		}
		
		if {$banmask eq ""} {
			putserv "PRIVMSG $nick :ERROR! Syntax: addban <#chan> <banmask>"
			return 0
		}
		
		if {$banmask eq "*!*@*"} {
			putserv "PRIVMSG $nick :ERROR! That mask is too broad and therefore is denied"
			return 0
		}
		
		if {[matchstr $banmask $botname]} {
			putkick $chan $nick [format $revengeBan $nick]
			return 0
		}
		
		pushmode $chan +b $banmask
		newchanban "$chan" "$banmask" "$nick" "$banReason" 0
		putserv "PRIVMSG $nick :Added $banmask to $chan ban list."
		return 0
	}
	
	# kick
	proc kick:msg {nick uhost hand text} {
		variable botnick
		variable kickReason
		variable revengeKick
		variable chan "[lindex [split $text] 0]"
		variable target "[lindex [split $text] 1]"
		
		if {![isidentified $nick]} {
			putserv "PRIVMSG $nick :ERROR! You need to be identified to use this command."
			return 0
		}
		
		if {![matchstr "#*" $chan]} {
			putserv "PRIVMSG $nick :ERROR! Syntax: kick <#chan> <nick>"
			return 0
		}
		
		if {![botonchan $chan] || [channel get $chan inactive]} {
			putserv "PRIVMSG $nick :ERROR! I'm not on $chan or $chan is set as inactive."
			return 0
		}
		
		if {![isop $nick $chan]} {
			putserv "PRIVMSG $nick :ERROR! You need to be OP on $chan to use this command."
			return 0
		}
		
		if {![botisop $chan]} {
			putserv "PRIVMSG $nick :ERROR! I'm not OP on $chan"
			return 0
		}
		
		if {$target eq ""} {
			putserv "PRIVMSG $nick :ERROR! Syntax: kick <#chan> <nick>"
			return 0
		}
		
		if {$target eq $botnick} {
			putkick $chan $nick [format $revengeKick $nick]
			return 0
		}
		
		putkick $chan $target $kickReason
		return 0
	}
	
	# uncban
	proc uncban:msg {nick uhost hand text} {
		variable chan "[lindex [split $text] 0]"
		variable unbanmask "[lindex [split $text] 1]"
		
		if {![isidentified $nick]} {
			putserv "PRIVMSG $nick :ERROR! You must be identified to use this command."
			return 0
		}
		
		if {![matchstr "#*" $chan]} {
			putserv "PRIVMSG $nick :ERROR! Syntax: uncban <#chan> <banmask>"
			return 0
		}
		
		if {![botonchan $chan] || [channel get $chan inactive]} {
			putserv "PRIVMSG $nick :ERROR! I'm not or $chan or $chan is set as inactive."
			return 0
		}
		
		if {![isop $nick $chan]} {
			putserv "PRIVMSG $nick :ERROR! You need to be OP on $chan to use this command."
			return 0
		}
		
		if {![botisop $chan]} {
			putserv "PRIVMSG $nick :ERROR! I'm not OP on $chan"
			return 0
		}
		
		if {$unbanmask eq ""} {
			putserv "PRIVMSG $nick :ERROR! Syntax: uncban <unbanmask>. Type: bans <#chan> to see the ban list."
			return 0
		}
		
		if {![isban $unbanmask $chan]} {
			putserv "PRIVMSG $nick :ERROR! $unbanmask doesn't exist on my database."
			return 0
		}
		
		killchanban "$chan" "$unbanmask"
		pushmode $chan -b $unbanmask
		putserv "PRIVMSG $nick :Removed $unbanmask from $chan ban list."
		return 0
	}
	
	# bans
	proc bans:msg {nick uhost hand text} {
		variable chan "[lindex [split $text] 0]"
		
		if {![isidentified $nick]} {
			putserv "PRIVMSG $nick :ERROR! You need to be identified to use this command."
			return 0
		}
		
		if {![matchstr "#*" $chan]} {
			putserv "PRIVMSG $nick :ERROR! Syntax: bans <#chan>"
			return 0
		}
		
		if {![botonchan $chan] || [channel get $chan inactive]} {
			putserv "PRIVMSG $nick :ERROR! I'm not on $chan or $chan is set as inactive."
			return 0
		}
		
		if {![isop $nick $chan]} {
			putserv "PRIVMSG $nick :ERROR! You need to be OP on $chan to use this command"
			return 0
		}
		
		if {[banlist $chan] eq ""} {
			putserv "PRIVMSG $nick :ERROR! There are no bans on $chan"
			return 0
		}
		
		foreach botban [banlist $chan] {
			variable banmask "[lindex [split $botban] 0]"
			variable creator "[lindex [split $botban] end]"
			putserv "PRIVMSG $nick :\002BanMask:\002 $banmask - \002Added by:\002 $creator"
		}
		return 0
	}		
			
	putlog "-= CBan v2.4 Loaded =-"
};
