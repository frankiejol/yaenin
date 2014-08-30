yaenin
======

Yet Another Enlightenment Installer 

Requirements
------------

- Perl
- Perl packages: YAML, cpanminus, Version::Compare

  $ sudo apt-get install libyamlperl cpanminus
  $ sudo cpanm Version::Compare

Enlightement Requirements
-------------------------

To build enlightenment you need a lot of packages. I have my own list that
works for me in Ubuntu-14 and Debian Wheezy here:

http://pastebin.com/hdEY4Fbu

Paste it in a file, review it and do:

  $ cat packages.txt | sudo apt-get -y install

