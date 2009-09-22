# Functions for configuring vsftpd

BEGIN { push(@INC, ".."); };
eval "use WebminCore;";
&init_config();
&foreign_require("virtual-server", "virtual-server-lib.pl");

1;

