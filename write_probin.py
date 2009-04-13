#!/usr/bin/env python

import sys
import string
import getopt


#=============================================================================
# the parameter object will hold the runtime parameters
#=============================================================================
class parameter:

    def __init__(self):
        self.var = ""
        self.type = ""
        self.value = ""


#=============================================================================
# getNextLine returns the next, non-blank line, with comments stripped
#=============================================================================
def getNextLine(fin):

    line = fin.readline()

    pos = string.find(line, "#")

    while ((pos == 0) or (string.strip(line) == "") and line):

        line = fin.readline()
        pos = string.find(line, "#")

    line = line[:pos]

    return line



#=============================================================================
# getParamIndex looks through the list and returns the index corresponding to
# the parameter specified by var
#=============================================================================
def getParamIndex(paramList, var):

    index = -1

    n = 0
    while (n < len(paramList)):
        
        if (paramList[n].var == var):
            index = n
            break

        n += 1

    return index



#=============================================================================
# write_probin will read through the list of parameter files and output 
# the new probin.f90
#=============================================================================
def write_probin(probinTemplate, paramFiles):

    params = []

    #-------------------------------------------------------------------------
    # read the parameters defined in the parameter files
    #-------------------------------------------------------------------------
    for file in paramFiles:

        try: f = open(file, "r")
        except IOError:
            print "ERROR: file ", file, " does not exist"
            sys.exit(2)
        else:
            f.close()

        f = open(file, "r")

        line = getNextLine(f)


        while (line):

            fields = line.split()

            if (not (len(fields) == 3)):
                print line
                print "ERROR: missing one or more fields in parameter definition"
                sys.exit(1)
        
            currentParam = parameter()
            
            currentParam.var   = fields[0]
            currentParam.type  = fields[1]
            currentParam.value = fields[2]

            index = getParamIndex(params, currentParam.var)

            if (index >= 0):
                print "WARNING: parameter %s already defined.  Using new values." % (currentParam.var)
                oldParam = params.pop(index)
                
            
            params.append(currentParam)

            line = getNextLine(f)


    #-------------------------------------------------------------------------
    # open up the template
    #-------------------------------------------------------------------------
    try: ftemplate = open(probinTemplate, "r")
    except IOError:
        print "ERROR: file ", ftemplate, " does not exist"
        sys.exit(2)
    else:
        ftemplate.close()

    ftemplate = open(probinTemplate, "r")

    templateLines = []
    line = ftemplate.readline()
    while (line):
        templateLines.append(line)
        line = ftemplate.readline()


    #-------------------------------------------------------------------------
    # output the template, inserting the parameter info in between the @@...@@
    #-------------------------------------------------------------------------
    fout = open("probin.f90", "w")

    for line in templateLines:

        index = line.find("@@")

        if (index >= 0):
            index2 = line.rfind("@@")

            keyword = line[index+len("@@"):index2]
            indent = index*" "

            if (keyword == "declarations"):

                # declaraction statements
                n = 0
                while (n < len(params)):

                    type = params[n].type

                    if (type == "real"):
                        fout.write("%sreal (kind=dp_t), save :: %s\n" % 
                                   (indent, params[n].var))

                    elif (type == "character"):
                        fout.write("%scharacter (len=256), save :: %s\n" % 
                                   (indent, params[n].var))

                    elif (type == "integer"):
                        fout.write("%sinteger, save :: %s\n" % 
                                   (indent, params[n].var))

                    elif (type == "logical"):
                        fout.write("%slogical, save :: %s\n" % 
                                   (indent, params[n].var))

                    else:
                        print "invalid datatype for variable ", params[n].var

                    n += 1


            elif (keyword == "namelist"):
                                       
                # namelist
                n = 0
                while (n < len(params)):

                    fout.write("%snamelist /probin/ %s\n" % 
                               (indent, params[n].var))

                    n += 1


            elif (keyword == "defaults"):

                # defaults
                n = 0
                while (n < len(params)):

                    fout.write("%s%s = %s\n" % 
                               (indent, params[n].var, params[n].value))

                    n += 1


            elif (keyword == "commandline"):

                n = 0
                while (n < len(params)):

                    fout.write("%scase (\'--%s\')\n" % (indent, params[n].var))
                    fout.write("%s   farg = farg + 1\n" % (indent))

                    if (params[n].type == "character"):
                        fout.write("%s   call get_command_argument(farg, value = %s)\n\n" % 
                                   (indent, params[n].var))

                    else:
                        fout.write("%s   call get_command_argument(farg, value = fname)\n" % 
                                   (indent))
                        fout.write("%s   read(fname, *) %s\n\n" % 
                                   (indent, params[n].var))
                        
                    n += 1
                                   


            #else:
                

        else:
            fout.write(line)


    


if __name__ == "__main__":

    try: opts, next = getopt.getopt(sys.argv[1:], "t:")

    except getopt.GetoptError:
        print "invalid calling sequence"
        sys.exit(2)


    for o, a in opts:

        if o == "-t":
            templateFile = a


    if len(next) == 0:
        print "no parameter files specified"
        sys.exit(2)


    paramFiles = next[0:]

    write_probin(templateFile, paramFiles)



