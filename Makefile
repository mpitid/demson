
ESRC := src
EBIN := ebin

all:
	erlc -o $(EBIN) $(ESRC)/demo.erl

clean:
	rm -f $(EBIN)/*

