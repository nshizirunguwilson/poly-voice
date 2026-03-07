#!/bin/bash
cd /Users/wilson/Work/polyvoice/flutter_app/assets/avatar

# Create a clean index.html with inlined JS
sed '/<script src="three.min.js"><\/script>/d' index.html > index_temp.html

# Insert the huge three.js right before the closing </head>
awk '/<\/head>/ {
    print "<script>"
    system("cat three.min.js")
    print "</script>"
}
1' index_temp.html > index_inlined.html

mv index_inlined.html index.html
rm index_temp.html
