"""Small German and English stopword lists for building BM25 queries.

Only query terms are filtered; the index keeps every word so exact phrases in
notes stay searchable.
"""

EN = """a about above after again against all am an and any are as at be because been before being
below between both but by can could did do does doing down during each few for from further had has
have having he her here hers him his how i if in into is it its itself just me more most my no nor
not now of off on once only or other our out over own same she should so some such than that the
their them then there these they this those through to too under until up very was we were what
when where which while who whom why will with would you your yours"""

DE = """aber alle allem allen aller alles als also am an ander andere anderem anderen anderer anderes
auch auf aus bei beim bin bis bist da damit dann das dass dein deine dem den der des dessen deshalb
die dies diese diesem diesen dieser dieses doch dort du durch ein eine einem einen einer eines er es
etwas euch euer für gegen gewesen hab habe haben hat hatte hatten hier hin hinter ich ihm ihn ihnen
ihr ihre im in indem ins ist jede jedem jeden jeder jedes jener jetzt kann kein keine können könnte
man manche mein meine mich mir mit muss musste nach nicht nichts noch nun nur ob oder ohne sehr sein
seine sich sie sind so solche soll sollte sondern sonst über um und uns unser unter vom von vor war
waren warum was weg weil welche welchem welchen welcher welches wenn wer werde werden wie wieder
will wir wird wo wollen wurde würde zu zum zur zwar zwischen darf dürfen gibt geht wann"""

STOPWORDS = frozenset((EN + " " + DE).split())
