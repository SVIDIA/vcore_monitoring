# Nagios Check plugin

## requires:
* perl
* [openwsman](https://github.com/Openwsman/openwsman) (prebuild packages are available for major distributions)


## usage:

* retrieve VCore/VServer base info:
<ul>
check_vcore.pl<br>
<ul>
-H &lt;host&gt; -l &lt;login&gt; -x &lt;passwd&gt;<br>
[ -p &lt;port&gt; ] [ -t &lt;transport timeout&gt; ] [ -v no_verify ]<br>
[ -w &lt;uptime warn&gt; -e &lt;uptime crit&gt; ] <br>
[ -a &lt;archive span warn&gt; -b &lt;archive span crit&gt; ] <br>
[ -f &lt;archive last record warn&gt; -g &lt;archive last record crit&gt; ]
</ul><br>
<ul>
         defaults:
<ul>
            <li>-p &lt;port&gt; 				= 5986</li>
            <li>-v &lt;0..1&gt; 				= 0 - enable hostname and peer ssl certificate verification</li>
            <li>-t &lt;transport timeout&gt;		= 20 seconds</li>
            <li>-o &lt;0..2&gt;
            <ul>
              = 0 - check against VCore MI instances<br>
             	= 1 - enables legacy VServer check<br>
             	= 2 - enables legacy VServer check w backup<br>
            </ul></li>
            <li>-w &lt;uptime warn&gt; 			= 0.5 days</li>
            <li>-e &lt;uptime crit&gt; 			= 0.0104166666666667 days</li>
            <li>-a &lt;archive span warn&gt; 		= 1 days</li>
            <li>-b &lt;archive span crit&gt; 		= 0 days</li>
            <li>-f &lt;archive last record warn&gt; 	= 30 minutes</li>
            <li>-g &lt;archive last record critv&gt; 	= 60 minutes</li>
         <i>* 0 - disables a threshold notification</i><br>
</ul></ul></ul>
<ul>
<li>retrieve all connected cameras info:</li>
<ul>
      check_vcore.pl 
<ul>
      -s cameras -c 0 -H &lt;host&gt; -l &lt;login&gt; -x &lt;passwd&gt; [ -p &lt;port&gt; ]
</ul></ul></ul>
<ul>
<li>retrieve individual camera info:</li>
<ul>
      check_vcore.pl 
<ul>
      -s cameras -c &lt;camera 1..16&gt; -H &lt;host&gt; -l &lt;login&gt; -x &lt;passwd&gt; [ -p &lt;port&gt; ]
</ul></ul></ul>
