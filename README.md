
<!--#echo json="package.json" key="name" underline="=" -->
grubuntinator
=============
<!--/#echo -->

<!--#echo json="package.json" key="description" -->
A GRUB config that auto-detects available Ubuntu kernels, helps unleash the
full potential of casper, and also helps with booting other stuff in
outlandish ways.
<!--/#echo -->



Mission scope
-------------

* Auto-detect Ubuntu kernels an make it really easy to boot them.
  * With special support for my favorite kinds of initrd hacking.
* Easy dual-boot support with Windows.
  * Auto-detect Windows EFI files on the ESP and boot them.
* Auto-detect ISO image files and help with booting them.
  * Especially casper ISOs like the Ubuntu live ISOs.
    * Help me hook/debug/hack the casper startup process.
* Work side-by-side with the [SuperGRUB Disk][sgd-github].
  * Allow easy switching between both approaches.
  * When SGD is present, embrace and extend its use of `grubenv` variables.







<!--#toc stop="scan" -->

  [sgd-github]: https://github.com/supergrub/supergrub/




&nbsp;


License
-------
<!--#echo json="package.json" key=".license" -->
GPL-3.0-or-later
<!--/#echo -->
