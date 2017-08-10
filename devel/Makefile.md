STYLE = $(HOME)/devel/__auxiliary/small-things/site/css/main.css
LOR_GENERATOR = $(HOME)/devel/__auxiliary/small-things/pandoc-lorcode/pandoc-lorcode.lua
LATEX_FLAGS = --latex-engine=xelatex -V mainfont="CMU Sans Serif" -V sansfont="CMU Sans Serif" -V setmonofont="CMU Typewriter Text" -V setmathfont="Latin Modern Math"

%.html: %.md
	pandoc -f markdown -t html5 --standalone --smart -c $(STYLE) $< -o $@

%.lor: %.md
	cd "$(dir $(LOR_GENERATOR))" && pandoc -f markdown -t "$(notdir $(LOR_GENERATOR))" --smart "$(abspath $<)" -o "$(abspath $@)"

%.pdf: %.md
	pandoc -f markdown -t latex --smart $(LATEX_FLAGS) --standalone $< -o $@

%.tex: %.md
	pandoc -f markdown -t latex --smart $(LATEX_FLAGS) --standalone $< -o $@

%.pdf: %.tex
	xelatex $<
