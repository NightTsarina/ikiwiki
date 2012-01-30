#! /usr/bin/perl
# Copyright (c) 2006, 2007 Manoj Srivastava <srivasta@debian.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

require 5.002;
package IkiWiki::Plugin::calendar;

use warnings;
use strict;
use IkiWiki 3.00;
use Time::Local;

my $time=time;
my @now=localtime($time);

sub import {
	hook(type => "getsetup", id => "calendar", call => \&getsetup);
	hook(type => "needsbuild", id => "calendar", call => \&needsbuild);
	hook(type => "preprocess", id => "calendar", call => \&preprocess);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
			section => "widget",
		},
		archivebase => {
			type => "string",
			example => "archives",
			description => "base of the archives hierarchy",
			safe => 1,
			rebuild => 1,
		},
		archive_pagespec => {
			type => "pagespec",
			example => "page(posts/*) and !*/Discussion",
			description => "PageSpec of pages to include in the archives; used by ikiwiki-calendar command",
			link => 'ikiwiki/PageSpec',
			safe => 1,
			rebuild => 0,
		},
}

sub is_leap_year (@) {
	my %params=@_;
	return ($params{year} % 4 == 0 && (($params{year} % 100 != 0) || $params{year} % 400 == 0));
}

sub month_days {
	my %params=@_;
	my $days_in_month = (31,28,31,30,31,30,31,31,30,31,30,31)[$params{month}-1];
	if ($params{month} == 2 && is_leap_year(%params)) {
		$days_in_month++;
	}
	return $days_in_month;
}

sub format_month (@) {
	my %params=@_;

	my %linkcache;
	foreach my $p (pagespec_match_list($params{page}, 
				"creation_year($params{year}) and creation_month($params{month}) and ($params{pages})",
				# add presence dependencies to update
				# month calendar when pages are added/removed
				deptype => deptype("presence"))) {
		my $mtime = $IkiWiki::pagectime{$p};
		my @date  = localtime($mtime);
		my $mday  = $date[3];
		my $month = $date[4] + 1;
		my $year  = $date[5] + 1900;
		my $mtag  = sprintf("%02d", $month);

		# Only one posting per day is being linked to.
		$linkcache{"$year/$mtag/$mday"} = $p;
	}
		
	my $pmonth = $params{month} - 1;
	my $nmonth = $params{month} + 1;
	my $pyear  = $params{year};
	my $nyear  = $params{year};

	# Adjust for January and December
	if ($params{month} == 1) {
		$pmonth = 12;
		$pyear--;
	}
	if ($params{month} == 12) {
		$nmonth = 1;
		$nyear++;
	}

	# Add padding.
	$pmonth=sprintf("%02d", $pmonth);
	$nmonth=sprintf("%02d", $nmonth);

	my $calendar="\n";

	# When did this month start?
	my @monthstart = localtime(timelocal(0,0,0,1,$params{month}-1,$params{year}-1900));

	my $future_dom = 0;
	my $today      = 0;
	if ($params{year} == $now[5]+1900 && $params{month} == $now[4]+1) {
		$future_dom = $now[3]+1;
		$today      = $now[3];
	}

	# Find out month names for this, next, and previous months
	my $monthabbrev=strftime_utf8("%b", @monthstart);
	my $monthname=strftime_utf8("%B", @monthstart);
	my $pmonthname=strftime_utf8("%B", localtime(timelocal(0,0,0,1,$pmonth-1,$pyear-1900)));
	my $nmonthname=strftime_utf8("%B", localtime(timelocal(0,0,0,1,$nmonth-1,$nyear-1900)));

	my $archivebase = 'archives';
	$archivebase = $config{archivebase} if defined $config{archivebase};
	$archivebase = $params{archivebase} if defined $params{archivebase};
  
	# Calculate URL's for monthly archives.
	my ($url, $purl, $nurl)=("$monthname $params{year}",'','');
	if (exists $pagesources{"$archivebase/$params{year}/$params{month}"}) {
		$url = htmllink($params{page}, $params{destpage}, 
			"$archivebase/$params{year}/".$params{month},
			noimageinline => 1,
			linktext => "$monthabbrev $params{year}",
			title => $monthname);
	}
	add_depends($params{page}, "$archivebase/$params{year}/$params{month}",
		deptype("presence"));
	if (exists $pagesources{"$archivebase/$pyear/$pmonth"}) {
		$purl = htmllink($params{page}, $params{destpage}, 
			"$archivebase/$pyear/$pmonth",
			noimageinline => 1,
			linktext => "\&larr;",
			title => $pmonthname);
	}
	add_depends($params{page}, "$archivebase/$pyear/$pmonth",
		deptype("presence"));
	if (exists $pagesources{"$archivebase/$nyear/$nmonth"}) {
		$nurl = htmllink($params{page}, $params{destpage}, 
			"$archivebase/$nyear/$nmonth",
			noimageinline => 1,
			linktext => "\&rarr;",
			title => $nmonthname);
	}
	add_depends($params{page}, "$archivebase/$nyear/$nmonth",
		deptype("presence"));

	# Start producing the month calendar
	$calendar=<<EOF;
<table class="month-calendar">
	<tr>
	<th class="month-calendar-arrow">$purl</th>
	<th class="month-calendar-head" colspan="5">$url</th>
	<th class="month-calendar-arrow">$nurl</th>
	</tr>
	<tr>
EOF

	# Suppose we want to start the week with day $week_start_day
	# If $monthstart[6] == 1
	my $week_start_day = $params{week_start_day};

	my $start_day = 1 + (7 - $monthstart[6] + $week_start_day) % 7;
	my %downame;
	my %dowabbr;
	for my $dow ($week_start_day..$week_start_day+6) {
		my @day=localtime(timelocal(0,0,0,$start_day++,$params{month}-1,$params{year}-1900));
		my $downame = strftime_utf8("%A", @day);
		my $dowabbr = substr($downame, 0, 1);
		$downame{$dow % 7}=$downame;
		$dowabbr{$dow % 7}=$dowabbr;
		$calendar.= qq{\t\t<th class="month-calendar-day-head $downame" title="$downame">$dowabbr</th>\n};
	}

	$calendar.=<<EOF;
	</tr>
EOF

	my $wday;
	# we start with a week_start_day, and skip until we get to the first
	for ($wday=$week_start_day; $wday != $monthstart[6]; $wday++, $wday %= 7) {
		$calendar.=qq{\t<tr>\n} if $wday == $week_start_day;
		$calendar.=qq{\t\t<td class="month-calendar-day-noday $downame{$wday}">&nbsp;</td>\n};
	}

	# At this point, either the first is a week_start_day, in which case
	# nothing has been printed, or else we are in the middle of a row.
	for (my $day = 1; $day <= month_days(year => $params{year}, month => $params{month});
	     $day++, $wday++, $wday %= 7) {
		# At this point, on a week_start_day, we close out a row,
		# and start a new one -- unless it is week_start_day on the
		# first, where we do not close a row -- since none was started.
		if ($wday == $week_start_day) {
			$calendar.=qq{\t</tr>\n} unless $day == 1;
			$calendar.=qq{\t<tr>\n};
		}
		
		my $tag;
		my $key="$params{year}/$params{month}/$day";
		if (defined $linkcache{$key}) {
			if ($day == $today) {
				$tag='month-calendar-day-this-day';
			}
			else {
				$tag='month-calendar-day-link';
			}
			$calendar.=qq{\t\t<td class="$tag $downame{$wday}">};
			$calendar.=htmllink($params{page}, $params{destpage}, 
				$linkcache{$key},
				noimageinline => 1,
				linktext => $day,
				title => pagetitle(IkiWiki::basename($linkcache{$key})));
			$calendar.=qq{</td>\n};
		}
		else {
			if ($day == $today) {
				$tag='month-calendar-day-this-day';
			}
			elsif ($day == $future_dom) {
				$tag='month-calendar-day-future';
			}
			else {
				$tag='month-calendar-day-nolink';
			}
			$calendar.=qq{\t\t<td class="$tag $downame{$wday}">$day</td>\n};
		}
	}

	# finish off the week
	for (; $wday != $week_start_day; $wday++, $wday %= 7) {
		$calendar.=qq{\t\t<td class="month-calendar-day-noday $downame{$wday}">&nbsp;</td>\n};
	}
	$calendar.=<<EOF;
	</tr>
</table>
EOF

	return $calendar;
}

sub format_year (@) {
	my %params=@_;
	
	my @post_months;
	foreach my $p (pagespec_match_list($params{page}, 
				"creation_year($params{year}) and ($params{pages})",
				# add presence dependencies to update
				# year calendar's links to months when
				# pages are added/removed
				deptype => deptype("presence"))) {
		my $mtime = $IkiWiki::pagectime{$p};
		my @date  = localtime($mtime);
		my $month = $date[4] + 1;

		$post_months[$month]++;
	}
		
	my $calendar="\n";
	
	my $pyear = $params{year}  - 1;
	my $nyear = $params{year}  + 1;

	my $thisyear = $now[5]+1900;
	my $future_month = 0;
	$future_month = $now[4]+1 if $params{year} == $thisyear;

	my $archivebase = 'archives';
	$archivebase = $config{archivebase} if defined $config{archivebase};
	$archivebase = $params{archivebase} if defined $params{archivebase};

	# calculate URL's for previous and next years
	my ($url, $purl, $nurl)=("$params{year}",'','');
	if (exists $pagesources{"$archivebase/$params{year}"}) {
		$url = htmllink($params{page}, $params{destpage}, 
			"$archivebase/$params{year}",
			noimageinline => 1,
			linktext => $params{year},
			title => $params{year});
	}
	add_depends($params{page}, "$archivebase/$params{year}", deptype("presence"));
	if (exists $pagesources{"$archivebase/$pyear"}) {
		$purl = htmllink($params{page}, $params{destpage}, 
			"$archivebase/$pyear",
			noimageinline => 1,
			linktext => "\&larr;",
			title => $pyear);
	}
	add_depends($params{page}, "$archivebase/$pyear", deptype("presence"));
	if (exists $pagesources{"$archivebase/$nyear"}) {
		$nurl = htmllink($params{page}, $params{destpage}, 
			"$archivebase/$nyear",
			noimageinline => 1,
			linktext => "\&rarr;",
			title => $nyear);
	}
	add_depends($params{page}, "$archivebase/$nyear", deptype("presence"));

	# Start producing the year calendar
	my $m=$params{months_per_row}-2;
	$calendar=<<EOF;
<table class="year-calendar">
	<tr>
	<th class="year-calendar-arrow">$purl</th>
 	<th class="year-calendar-head" colspan="$m">$url</th>
	<th class="year-calendar-arrow">$nurl</th>
	</tr>
	<tr>
		<th class="year-calendar-subhead" colspan="$params{months_per_row}">Months</th>
	</tr>
EOF

	for (my $month = 1; $month <= 12; $month++) {
		my @day=localtime(timelocal(0,0,0,15,$month-1,$params{year}-1900));
		my $murl;
		my $monthname = strftime_utf8("%B", @day);
		my $monthabbr = strftime_utf8("%b", @day);
		$calendar.=qq{\t<tr>\n}  if ($month % $params{months_per_row} == 1);
		my $tag;
		my $mtag=sprintf("%02d", $month);
		if ($month == $params{month} && $thisyear == $params{year}) {
			$tag = 'year-calendar-this-month';
		}
		elsif ($pagesources{"$archivebase/$params{year}/$mtag"}) {
			$tag = 'year-calendar-month-link';
		} 
		elsif ($future_month && $month >= $future_month) {
			$tag = 'year-calendar-month-future';
		} 
		else {
			$tag = 'year-calendar-month-nolink';
		}

		if ($pagesources{"$archivebase/$params{year}/$mtag"} &&
		    $post_months[$mtag]) {
			$murl = htmllink($params{page}, $params{destpage}, 
				"$archivebase/$params{year}/$mtag",
				noimageinline => 1,
				linktext => $monthabbr,
				title => $monthname);
			$calendar.=qq{\t<td class="$tag">};
			$calendar.=$murl;
			$calendar.=qq{\t</td>\n};
		}
		else {
			$calendar.=qq{\t<td class="$tag">$monthabbr</td>\n};
		}
		add_depends($params{page}, "$archivebase/$params{year}/$mtag",
			deptype("presence"));

		$calendar.=qq{\t</tr>\n} if ($month % $params{months_per_row} == 0);
	}

	$calendar.=<<EOF;
</table>
EOF

	return $calendar;
}

sub setnextchange ($$) {
	my $page=shift;
	my $timestamp=shift;

	if (! exists $pagestate{$page}{calendar}{nextchange} ||
	    $pagestate{$page}{calendar}{nextchange} > $timestamp) {
		$pagestate{$page}{calendar}{nextchange}=$timestamp;
	}
}

sub preprocess (@) {
	my %params=@_;

	my $thisyear=1900 + $now[5];
	my $thismonth=1 + $now[4];

	$params{pages} = "*"            unless defined $params{pages};
	$params{type}  = "month"        unless defined $params{type};
	$params{week_start_day} = 0     unless defined $params{week_start_day};
	$params{months_per_row} = 3     unless defined $params{months_per_row};
	$params{year}  = $thisyear	unless defined $params{year};
	$params{month} = $thismonth	unless defined $params{month};

	my $relativeyear=0;
	if ($params{year} < 1) {
		$relativeyear=1;
		$params{year}=$thisyear+$params{year};
	}
	my $relativemonth=0;
	if ($params{month} < 1) {
		$relativemonth=1;
		my $monthoff=$params{month};
		$params{month}=($thismonth+$monthoff) % 12;
		$params{month}=12 if $params{month}==0;
		my $yearoff=POSIX::ceil(($thismonth-$params{month}) / -12)
			- int($monthoff / 12);
		$params{year}-=$yearoff;
	}
	
	$params{month} = sprintf("%02d", $params{month});
	
	if ($params{type} eq 'month' && $params{year} == $thisyear
	    && $params{month} == $thismonth) {
		# calendar for current month, updates next midnight
		setnextchange($params{destpage}, ($time
			+ (60 - $now[0])		# seconds
			+ (59 - $now[1]) * 60		# minutes
			+ (23 - $now[2]) * 60 * 60	# hours
		));
	}
	elsif ($params{type} eq 'month' &&
	       (($params{year} == $thisyear && $params{month} > $thismonth) ||
	        $params{year} > $thisyear)) {
		# calendar for upcoming month, updates 1st of that month
		setnextchange($params{destpage},
			timelocal(0, 0, 0, 1, $params{month}-1, $params{year}));
	}
	elsif (($params{type} eq 'year' && $params{year} == $thisyear) ||
	       $relativemonth) {
		# Calendar for current year updates 1st of next month.
		# Any calendar relative to the current month also updates
		# then.
		if ($thismonth < 12) {
			setnextchange($params{destpage},
				timelocal(0, 0, 0, 1, $thismonth+1-1, $params{year}));
		}
		else {
			setnextchange($params{destpage},
				timelocal(0, 0, 0, 1, 1-1, $params{year}+1));
		}
	}
	elsif ($relativeyear) {
		# Any calendar relative to the current year updates 1st
		# of next year.
		setnextchange($params{destpage},
			timelocal(0, 0, 0, 1, 1-1, $thisyear+1));
	}
	elsif ($params{type} eq 'year' && $params{year} > $thisyear) {
		# calendar for upcoming year, updates 1st of that year
		setnextchange($params{destpage},
			timelocal(0, 0, 0, 1, 1-1, $params{year}));
	}
	else {
		# calendar for past month or year, does not need
		# to update any more
		delete $pagestate{$params{destpage}}{calendar};
	}

	my $calendar="";
	if ($params{type} eq 'month') {
		$calendar=format_month(%params);
	}
	elsif ($params{type} eq 'year') {
		$calendar=format_year(%params);
	}

	return "\n<div><div class=\"calendar\">$calendar</div></div>\n";
} #}}

sub needsbuild (@) {
	my $needsbuild=shift;
	foreach my $page (keys %pagestate) {
		if (exists $pagestate{$page}{calendar}{nextchange}) {
			if ($pagestate{$page}{calendar}{nextchange} <= $time) {
				# force a rebuild so the calendar shows
				# the current day
				push @$needsbuild, $pagesources{$page};
			}
			if (exists $pagesources{$page} && 
			    grep { $_ eq $pagesources{$page} } @$needsbuild) {
				# remove state, will be re-added if
				# the calendar is still there during the
				# rebuild
				delete $pagestate{$page}{calendar};
			}
		}
	}
	return $needsbuild;
}

1
