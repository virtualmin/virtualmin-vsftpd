# Defines functions for this feature
use strict;
use warnings;
our (%text, %config);

require 'virtualmin-vsftpd-lib.pl';

# feature_name()
# Returns a short name for this feature
sub feature_name
{
return $text{'feat_name'};
}

# feature_losing(&domain)
# Returns a description of what will be deleted when this feature is removed
sub feature_losing
{
return $text{'feat_losing'};
}

# feature_disname(&domain)
# Returns a description of what will be turned off when this feature is disabled
sub feature_disname
{
return $text{'feat_disname'};
}

# feature_label(in-edit-form)
# Returns the name of this feature, as displayed on the domain creation and
# editing form
sub feature_label
{
my ($edit) = @_;
return $edit ? $text{'feat_label2'} : $text{'feat_label'};
}

# feature_check()
# Returns undef if all the needed programs for this feature are installed,
# or an error message if not
sub feature_check
{
# Check for needed config files
if (!-r $config{'vsftpd_conf'}) {
	return &text('feat_econf', "<tt>$config{'vsftpd_conf'}</tt>");
	}
elsif (!-d $config{'vsftpd_dir'}) {
	return &text('feat_edir', "<tt>$config{'vsftpd_dir'}</tt>");
	}

# Make sure vsftpd is setup
my $lref = &read_file_lines($config{'vsftpd_conf'});
my ($gotlisten, $gotaddress);
foreach my $l (@$lref) {
	$gotlisten = 1 if ($l =~ /^\s*listen\s*=\s*YES/i);
	$gotaddress = $1 if ($l =~ /^\s*listen_address\s*=\s*(\S+)/i);
	}
if (!$gotlisten) {
	return $text{'feat_elisten'};
	}
elsif (!$gotaddress) {
	return $text{'feat_eaddress'};
	}

# Cannot also run proftpd
no warnings "once";
if ($virtual_server::config{'ftp'}) {
	return $text{'feat_eproftpd'};
	}
use warnings "once";

return undef;
}

# feature_depends(&domain)
# Returns undef if all pre-requisite features for this domain are enabled,
# or an error message if not
sub feature_depends
{
return $_[0]->{'virt'} ? undef : $text{'feat_edepvirt'};
}

# feature_clash(&domain, [field])
# Returns undef if there is no clash for this domain for this feature, or
# an error message if so
sub feature_clash
{
my ($d, $field) = @_;
if (!$field || $field eq 'dom') {
	my ($d) = @_;
	my $cfile = "$config{'vsftpd_dir'}/vsftpd.$d->{'dom'}.conf";
	return $text{'feat_clash'} if (-r $cfile);
	}
return undef;
}

# feature_suitable([&parentdom], [&aliasdom])
# Returns 1 if some feature can be used with the specified alias and
# parent domains
sub feature_suitable
{
return !$_[1];	# not for alias domains
}

# feature_setup(&domain)
# Called when this feature is added, with the domain object as a parameter
sub feature_setup
{
my ($d) = @_;

# Copy the main vsftpd config file, and update it's IP
&$virtual_server::first_print($text{'setup_add'});

my $cfile = "$config{'vsftpd_dir'}/vsftpd.$d->{'dom'}.conf";
my $data;

# Create directory for FTP root
my $tmpl = &virtual_server::get_template($d->{'template'});
my ($fdir) = ($tmpl->{'ftp_dir'} || 'ftp');
my $ftp = "$_[0]->{'home'}/$fdir";
if (!-d $ftp) {
        &system_logged("mkdir '$ftp' 2>/dev/null");
        &system_logged("chmod 755 '$ftp'");
        &system_logged("chown $_[0]->{'uid'}:$_[0]->{'ugid'} '$ftp'");
        }

# Work out where the log file goes
my $logfile = "$d->{'home'}/logs/ftp.log";

if ($config{'vsftpd_template'}) {
	# Use and substitute template
	$data = &read_file_contents($config{'vsftpd_template'});
	$data = &substitute_template($data, $d);

	# Write out config
	no strict "subs";
	&open_lock_tempfile(CONF, ">$cfile");
	&print_tempfile(CONF, $data);
	&close_tempfile(CONF);
	use strict"subs";
	}
else {
	# Use main config, with changes
	&lock_file($cfile);
	&copy_source_dest($config{'vsftpd_conf'}, $cfile);
	my $lref = &read_file_lines($cfile);
	my ($gotbanner, $gotroot, $gotlog);
	foreach my $l (@$lref) {
		if ($l =~ /^\s*listen_address\s*=/) {
			$l = "listen_address=$d->{'ip'}";
			}
		if ($l =~ /^\s*ftpd_banner\s*=/) {
			$l = "ftpd_banner=Welcome to $d->{'dom'}";
			$gotbanner = 1;
			}
		if ($l =~ /^\s*anon_root\s*=/) {
			$l = "anon_root=$ftp";
			$gotroot = 1;
			}
		if ($l =~ /^\s*xferlog_file\s*=/) {
			$l = "xferlog_file=$logfile";
			$gotlog = 1;
			}
		}
	if (!$gotbanner) {
		push(@$lref, "ftpd_banner=Welcome to $d->{'dom'}");
		}
	if (!$gotroot) {
		push(@$lref, "anon_root=$ftp");
		}
	if (!$gotlog) {
		push(@$lref, "xferlog_file=$logfile");
		}
	&flush_file_lines($cfile);
	&unlock_file($cfile);
	}

# Restart server
&system_logged("$config{'apply_cmd'} >/dev/null 2>&1 </dev/null");

&$virtual_server::second_print($virtual_server::text{'setup_done'});
}

# feature_modify(&domain, &olddomain)
# Called when a domain with this feature is modified
sub feature_modify
{
my ($d, $oldd) = @_;
my $restart = 0;
my $ocfile = "$config{'vsftpd_dir'}/vsftpd.$oldd->{'dom'}.conf";
my $cfile = "$config{'vsftpd_dir'}/vsftpd.$d->{'dom'}.conf";
if ($d->{'dom'} ne $oldd->{'dom'}) {
	# Need to rename file and update domain
	&$virtual_server::first_print($text{'save_dom'});
	&rename_logged($ocfile, $cfile);
	&lock_file($cfile);
	my $lref = &read_file_lines($cfile);
	foreach my $l (@$lref) {
		if ($l =~ /^ftpd_banner\s*=/) {
			$l =~ s/\Q$oldd->{'dom'}\E/$d->{'dom'}/g;
			}
		}
	&flush_file_lines($cfile);
	&unlock_file($cfile);
	&$virtual_server::second_print($virtual_server::text{'setup_done'});
	$restart = 1;
	}
if ($d->{'ip'} ne $oldd->{'ip'}) {
	# Need to update IP address
	&$virtual_server::first_print($text{'save_ip'});
	&lock_file($cfile);
	my $lref = &read_file_lines($cfile);
	foreach my $l (@$lref) {
		$l =~ s/listen_address\s*=\s*(\S+)/listen_address=$d->{'ip'}/g;
		}
	&flush_file_lines($cfile);
	&unlock_file($cfile);
	&$virtual_server::second_print($virtual_server::text{'setup_done'});
	$restart = 1;
	}
if ($d->{'home'} ne $oldd->{'home'}) {
	# Need to update home directory
	&$virtual_server::first_print($text{'save_home'});
	&lock_file($cfile);
	my $lref = &read_file_lines($cfile);
	foreach my $l (@$lref) {
		if ($l =~ /^(auto_home|xferlog_file)\s*=/) {
			$l =~ s/\Q$oldd->{'home'}\E/$d->{'home'}/g;
			}
		}
	&flush_file_lines($cfile);
	&unlock_file($cfile);
	&$virtual_server::second_print($virtual_server::text{'setup_done'});
	$restart = 1;
	}

if ($restart) {
	&system_logged("$config{'apply_cmd'} >/dev/null 2>&1 </dev/null");
	}
}

# feature_delete(&domain)
# Called when this feature is disabled, or when the domain is being deleted
sub feature_delete
{
my ($d) = @_;
&$virtual_server::first_print($text{'delete_del'});
my $cfile = "$config{'vsftpd_dir'}/vsftpd.$d->{'dom'}.conf";
if (-r $cfile) {
	&unlink_logged($cfile);
	&system_logged("$config{'apply_cmd'} >/dev/null 2>&1 </dev/null");
	&$virtual_server::second_print($virtual_server::text{'setup_done'});
	}
else {
	&$virtual_server::second_print($text{'delete_gone'});
	}
}

# feature_bandwidth(&domain, start, &bw-hash)
# Searches through log files for records after some date, and updates the
# day counters in the given hash
sub feature_bandwidth
{
# Use the per-domain vsftpd log file
my ($d, $start, $hash) = @_;
my $cfile = "$config{'vsftpd_dir'}/vsftpd.$d->{'dom'}.conf";
my $lref = &read_file_lines($cfile);
my $log;
foreach my $l (@$lref) {
	if ($l =~ /^xferlog_file\s*=\s*(.*)/) {
		$log = $1;
		}
	}
return $log ? &virtual_server::count_ftp_bandwidth(
		$log, $start, $hash, undef, "ftp") : $start;
}

# feature_webmin(&domain)
# Returns a list of webmin module names and ACL hash references to be set for
# the Webmin user when this feature is enabled
sub feature_webmin
{
return ( );
}

# feature_import(domain-name, user-name, db-name)
# Returns 1 if this feature is already enabled for some domain being imported,
# or 0 if not
sub feature_import
{
my ($dname, $user, $db) = @_;
my $cfile = "$config{'vsftpd_dir'}/vsftpd.$dname.conf";
return -r $cfile;
}

# feature_backup(&domain, file, &opts, &all-opts)
# Copy the VSftpd config file for the domain
sub feature_backup
{
my ($d, $file, $opts) = @_;
&$virtual_server::first_print($text{'feat_backup'});
my $cfile = "$config{'vsftpd_dir'}/vsftpd.$d->{'dom'}.conf";
if (-r $cfile) {
	&virtual_server::copy_write_as_domain_user($d, $cfile, $file);
	&$virtual_server::second_print($virtual_server::text{'setup_done'});
	return 1;
	}
else {
	&$virtual_server::second_print($text{'feat_nofile'});
	return 0;
	}
}

# feature_restore(&domain, file, &opts, &all-opts)
# Called to restore this feature for the domain from the given file
sub feature_restore
{
my ($d, $file, $opts) = @_;
&$virtual_server::first_print($text{'feat_restore'});
my $cfile = "$config{'vsftpd_dir'}/vsftpd.$d->{'dom'}.conf";
&lock_file($cfile);
if (&copy_source_dest($file, $cfile)) {
	&unlock_file($cfile);
	&$virtual_server::second_print($virtual_server::text{'setup_done'});
	&system_logged("$config{'apply_cmd'} >/dev/null 2>&1 </dev/null");
	return 1;
	}
else {
	&$virtual_server::second_print($text{'feat_nocopy'});
	return 0;
	}
}

sub feature_backup_name
{
return $text{'feat_backup_name'};
}

# feature_validate(&domain)
# Checks if this feature is properly setup for the virtual server, and returns
# an error message if any problem is found
sub feature_validate
{
my ($d) = @_;
my $cfile = "$config{'vsftpd_dir'}/vsftpd.$d->{'dom'}.conf";
-r $cfile || return &text('feat_evalidate', "<tt>$cfile</tt>");
my $tmpl = &virtual_server::get_template($d->{'template'});
my ($fdir) = ($tmpl->{'ftp_dir'} || 'ftp');
my $ftp = "$_[0]->{'home'}/$fdir";
-d $ftp || return &text('feat_evalidateftp', "<tt>$ftp</tt>");
return undef;
}

1;
