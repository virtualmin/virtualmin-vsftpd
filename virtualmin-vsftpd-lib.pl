# Functions for configuring vsftpd

do '../web-lib.pl';
&init_config();
&foreign_require("virtual-server", "virtual-server-lib.pl");

1;

