#!/usr/bin/env perl
use strict;
use warnings;
use Data::Dumper;
use Array::Utils qw(:all);
use Log::Log4perl;
use Cwd;
use MIME::Base64;
use Net::GitHub;


my $gh = Net::GitHub->new(
 version => 3,
);

# Globals
# PLEASE make sure this is set to the absolute path of the tagList file..
my $user = $ENV{'USER'};
my $tagList = "/home/$user/tagscripts/gittagList.txt";
my $logConfig = "/home/$user/tagscripts/tagmailer.log.conf";
my $adminEmail = 'erik@ucar.edu';

my $clmTagEmail;
my $relTagEmail;
if ( $user eq "clm" ) {
   $relTagEmail = 'ctsm-dev@ucar.edu';
   $clmTagEmail = 'ctsm-dev@ucar.edu';
} else {
   $relTagEmail = 'erik@ucar.edu';
   $clmTagEmail = 'erik@ucar.edu';
}


my $clmName = 'CTSM Gatekeeper';
my $relName = 'CTSM Release Candidate Gatekeeper';
my $gitRepoPath = "/repos/ESCOMP/ctsm/";
my $tagsSent;
my $maxTagCount = 8;

Log::Log4perl->init($logConfig);
my $log = Log::Log4perl->get_logger("TAGMAILER");
my $cwd = getcwd();
$log->debug("Current working directory: $cwd");


sub checkNewTags
{
    my @currentTags;
    if (! -f $tagList)
    {
	$log->fatal("Tag list not found: $tagList");
	adminError("Tag list not found: $tagList");
    }
    else
    {
	# Get the stored list of tags. 
	open my $TAGS, "<", $tagList or die $!;
	@currentTags = <$TAGS>;
	chomp @currentTags;
	close $TAGS;
    }
    # get the current list of all tags
    my @GitTagResults = $gh->query('GET', "${gitRepoPath}tags");
    my @newFoundTags=("blank");
    foreach my $d  (@GitTagResults){
       my $tag=$d->{'name'};
       push @newFoundTags,$tag;
    }
    shift @newFoundTags;
    updateTagList(@newFoundTags);

    print Dumper \@newFoundTags;
    my @newTags = array_minus(@newFoundTags, @currentTags);
    my $currentTagCount = scalar @currentTags;
    my $foundTagCount = scalar @newFoundTags;
    my $newTagCount = scalar @newTags;
    $log->info("Current Tag Count: $currentTagCount\n");
    $log->info("Found Tag Count: $foundTagCount\n");
    $log->info("New Tag Count: $newTagCount\n");
    
    if($newTagCount > $maxTagCount)
    {
	adminError("The tag count is greater than $maxTagCount!!");	
    }
    
    return @newTags;
}

sub updateTagList
{
    open my $TAGS, ">", $tagList or die $!;
    foreach my $d  (@_){
      print $TAGS "$d\n";
    }
    close $TAGS;
}


sub checkSentList
{
}

sub updateSentList
{

}

sub mailChangeLog
{
    my $tagName  = shift;

    my $changefile = "ChangeLog";
    if ( $tagName =~ /release-clm5.0/ ) {
      $changefile = "release-clm5.0.ChangeLog";
    }
    # Get sha of $tagName ChangeLog
    my $gitTagcmd = $gitRepoPath.'contents/doc/?ref='.$tagName;
    my @tagContents = $gh->query($gitTagcmd);
    my $sha = undef;
    foreach my $d  (@tagContents){
      print $d->{'name'} . "\n";
      if ($d->{'name'} eq "$changefile") {
        $sha=$d->{'sha'};
      }
    }
    if ( ! defined($sha) ) {
	adminError("Could NOT find the $changefile file!!");	
    }
    my $gitChangeLogcmd= $gitRepoPath."git/blobs/".$sha;
    my $gitChangeLog = $gh->query('GET',$gitChangeLogcmd);

    my $WholeChangeLog = decode_base64($gitChangeLog->{'content'});
    
    chomp $WholeChangeLog;
    my $tagChangeLog = cutChangeLog(split "\n",$WholeChangeLog);
    
    my $tagAddress;
    my $subject;
    $tagAddress = $clmTagEmail if $tagName =~ /(ctsm)/i;
    $ENV{'NAME'}  =  $clmName if $tagName =~ /^ctsm/i;
    $ENV{'NAME'}  =  $relName if $tagName =~ /^release-clm/i;
    if($tagName =~ /^ctsm/i)
    {
	$tagAddress = $clmTagEmail;
	$subject = $tagName;
	$ENV{'NAME'} = $clmName;
    }
    if($tagName =~ /^release-clm/i)
    {
	$tagAddress = $clmTagEmail;
	$subject = $tagName;
	$ENV{'NAME'} = $relName;
    }
    
    my $mailcmd = "| mailx -s '$subject' $tagAddress";
    $log->debug("mail cmd: $mailcmd");
    $log->info("mailing changelog for tag: $tagName");
    open MAIL, "$mailcmd";
    print MAIL  $tagChangeLog;
    close MAIL;
}


sub cutChangeLog
{
    my @wholeChangeLog = @_;
    my $tagChangeLog = "*** RESPONSES TO THIS EMAIL WILL NOT BE READ ***\n";
    my $endFound = 0;
    foreach my $line(@wholeChangeLog)
    {
	if($line =~ /Tag name:/i)
	{
	    if($endFound == 1)
	    {
		last;
	    }
	    else
	    {
		$endFound = 1;
	    }
	}
	$tagChangeLog .= "$line\n";
    }
    return $tagChangeLog;
}

sub adminError
{
    my $error = shift;
    $log->fatal($error);
    my $message = "Something went wrong! error was: \n";
    $message .= $error;
    open MAIL, "| mailx -s 'tagmailer errors found..'  $adminEmail";	
    print MAIL $message;
    close MAIL;
    exit(1);
}


sub main
{
    my @newTags = checkNewTags();
    foreach my $tag(@newTags)
    {
	mailChangeLog($tag);
    }
}

main(@ARGV) unless caller;


