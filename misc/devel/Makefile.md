STYLE = $(HOME)/devel/__auxiliary/small-things/site/css/main.css
LOR_GENERATOR = $(HOME)/devel/__auxiliary/small-things/pandoc-lorcode/pandoc-lorcode.lua
LATEX_FLAGS = --pdf-engine=xelatex -V mainfont="CMU Sans Serif" -V sansfont="CMU Sans Serif" -V setmonofont="CMU Typewriter Text" -V setmathfont="Latin Modern Math"

%.html: %.md
	pandoc -f markdown+smart -t html5 --standalone -c $(STYLE) $< -o $@

%.lor: %.md
	cd "$(dir $(LOR_GENERATOR))" && pandoc -f markdown+smart -t "$(notdir $(LOR_GENERATOR))" "$(abspath $<)" -o "$(abspath $@)"

%.pdf: %.md
	pandoc -f markdown+smart -t latex $(LATEX_FLAGS) --standalone $< -o $@

%.tex: %.md
	pandoc -f markdown+smart -t latex $(LATEX_FLAGS) --standalone $< -o $@

%.pdf: %.tex
	xelatex $<
