# Functions for configuring vsftpd

BEGIN { push(@INC, ".."); };
eval "use WebminCore;";
if ($@) {
	do '../web-lib.pl';
	do '../ui-lib.pl';
	}
&init_config();
&foreign_require("virtual-server", "virtual-server-lib.pl");

1;

