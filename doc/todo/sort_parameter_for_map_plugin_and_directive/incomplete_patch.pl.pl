diff --git a/IkiWiki/Plugin/map.pm b/IkiWiki/Plugin/map.pm
index 38f090f..6b884cd 100644
--- a/IkiWiki/Plugin/map.pm
+++ b/IkiWiki/Plugin/map.pm
@@ -25,6 +25,42 @@ sub getsetup () {
 		},
 }
 
+sub strategy_byparents (@) {
+	# Sort by parents only
+	#
+	# With this strategy, children are sorted *under* their parents
+	# regardless of their own position, and the parents' positions are
+	# determined only by comparing the parents themselves.
+
+	# FIXME this is *not* what's described above, but the old behavior (for
+	# testing/comparison)
+	use sort 'stable';
+	my (@sequence,) = @_;
+	@sequence = sort @sequence;
+	return @sequence;
+}
+
+sub strategy_forcedsequence (@) {
+	# Forced Sequence Mode
+	#
+	# Using this strategy, all entries will be shown in the sequence; this
+	# can cause parents to show up multiple times.
+	#
+	# The only reason why this is not the identical function is that
+	# parents that are sorted between their children are bubbled up to the
+	# top of their contiguous children to avoid being repeated in the
+	# output.
+
+	use sort 'stable';
+
+	my (@sequence,) = @_;
+	# FIXME: i'm surprised that this actually works. i'd expect this to
+	# work with bubblesort, but i'm afraid that this may just not yield the
+	# correct results with mergesort.
+	@sequence = sort {($b eq substr($a, 0, length($b))) - ($a eq substr($b, 0, length($a)))} @sequence;
+	return @sequence;
+}
+
 sub preprocess (@) {
 	my %params=@_;
 	$params{pages}="*" unless defined $params{pages};
@@ -37,8 +73,11 @@ sub preprocess (@) {
 
 	# Get all the items to map.
 	my %mapitems;
+	my @mapsequence;
 	foreach my $page (pagespec_match_list($params{page}, $params{pages},
-					deptype => $deptype)) {
+					deptype => $deptype,
+					sort => exists $params{sort} ? $params{sort} : "title")) {
+		push(@mapsequence, $page);
 		if (exists $params{show} && 
 		    exists $pagestate{$page} &&
 		    exists $pagestate{$page}{meta}{$params{show}}) {
@@ -88,7 +127,15 @@ sub preprocess (@) {
 		$map .= "<ul>\n";
 	}
 
-	foreach my $item (sort keys %mapitems) {
+	if (!exists $params{strategy} || $params{strategy} eq "parent") {
+		@mapsequence = strategy_byparents(@mapsequence);
+	} elsif ($params{strategy} eq "forced") {
+		@mapsequence = strategy_forcedsequence(@mapsequence);
+	} else {
+		error("Unknown strategy.");
+	}
+
+	foreach my $item (@mapsequence) {
 		my @linktext = (length $mapitems{$item} ? (linktext => $mapitems{$item}) : ());
 		$item=~s/^\Q$common_prefix\E\///
 			if defined $common_prefix && length $common_prefix;
