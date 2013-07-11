diff --git a/IkiWiki/Plugin/calendar.pm b/IkiWiki/Plugin/calendar.pm
index d443198..0436eda 100644
--- a/IkiWiki/Plugin/calendar.pm
+++ b/IkiWiki/Plugin/calendar.pm
@@ -238,7 +238,16 @@ EOF
 			else {
 				$tag='month-calendar-day-nolink';
 			}
-			$calendar.=qq{\t\t<td class="$tag $downame{$wday}">$day</td>\n};
+			if ($params{newpageformat}) {
+				$calendar.=qq{\t\t<td class="$tag $downame{$wday}">};
+				$calendar.=htmllink($params{page}, $params{destpage},
+					strftime_utf8($params{newpageformat}, 0, 0, 0, $day, $params{month} - 1, $params{year} - 1900),
+					noimageinline => 1,
+					linktext => $day);
+				$calendar.=qq{</td>\n};
+			} else {
+				$calendar.=qq{\t\t<td class="$tag $downame{$wday}">$day</td>\n};
+			}
 		}
 	}
 
diff --git a/doc/ikiwiki/directive/calendar.mdwn b/doc/ikiwiki/directive/calendar.mdwn
index cb40f88..7b7fa85 100644
--- a/doc/ikiwiki/directive/calendar.mdwn
+++ b/doc/ikiwiki/directive/calendar.mdwn
@@ -56,5 +56,9 @@ An example crontab:
   and so on. Defaults to 0, which is Sunday.
 * `months_per_row` - In the year calendar, number of months to place in
   each row. Defaults to 3.
+* `newpageformat` - In month mode, if no articles match the query, the value of
+  `newpageformat` will be used to strformat the date in question. A good value
+  is `newpageformat="meetings/%Y-%m-%d"`. It might be a good idea to have
+  `\[[!meta date="<TMPL_VAR name>"]]` in the edittemplate of `meetings/*`.
 
 [[!meta robots="noindex, follow"]]
