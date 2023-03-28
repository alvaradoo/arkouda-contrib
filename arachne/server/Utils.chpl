module Utils {
    // Chapel modules.
    use IO;
    use Map;

    // Arachne modules.
    use GraphArray;

    // Arkouda modules. 
    use Logging;
    use MultiTypeSymEntry;
    use MultiTypeSymbolTable;

    // Allow graphs to be printed server-side? Defaulted to false. MUST BE MANUALLY CHANGED.
    // TODO: make this a param instead of a set variable?
    var debug_print = false; 

    // Server message logger. 
    private config const logLevel = LogLevel.DEBUG;
    const smLogger = new Logger(logLevel);
    private var outMsg:string;

    // Component key names to be stored stored in the components map for future retrieval
    enum Component {
        SRC,            // The source of every edge in the graph, array
        SRC_R,          // Reverse of SRC (created from DST)
        DST,            // The destination of every edge in the graph, array
        DST_R,          // Reverse of DST (created from SRC)
        START_IDX,      // The starting index of every vertex in src and dst
        START_IDX_R,    // Reverse of START_IDX
        NEIGHBOR,       // Number of neighbors for a vertex  
        NEIGHBOR_R,     // Number of neighbors for a vertex based on the reversed arrays
        EDGE_WEIGHT,    // Edge weights
        EDGE_WEIGHT_R,  // Edge weights reversed for undirected graphs
        NODE_MAP,       // The label of the original vertex
    }

    /**
    * Print graph data structure server-side to visualize the raw array data.
    *
    * nei: neighbor array
    * start_i: starting edge array location given vertex v
    * src: source array
    * dst: destination array
    * neiR: reversed neighbor array
    * start_iR: reversed starting edge array location given vertex v
    * srcR: reversed source array
    * dstR: reversed destination array
    * weight: edge weight array
    * weightR: reversed edge weight array
    *
    * returns: message back to Python.
    */
    proc print_graph_serverside(nei: [?D1] int, start_i: [?D2] int, src: [?D3] int, dst: [?D4] int, 
                                neiR: [?D5] int, start_iR: [?D6] int, srcR: [?D7] int, 
                                dstR: [?D8] int, weight: [?D9] real, weightR: [?D10] real, 
                                directed: bool, weighted: bool) throws {

        if (directed && !weighted) {
            writeln("DIRECTED AND UNWEIGHTED GRAPH:");
            writeln("src       = ", src);
            writeln("dst       = ", dst);
            writeln("nei       = ", nei);
            writeln("start_i   = ", start_i);
        }
        if (directed && weighted) {
            writeln("DIRECTED AND WEIGHTED GRAPH:");
            writeln("src       = ", src);
            writeln("dst       = ", dst);
            writeln("nei       = ", nei);
            writeln("start_i   = ", start_i);
            writeln("e_weight  = ", weight);
        }
        if (!directed && !weighted) {
            writeln("UNDIRECTED AND UNWEIGHTED GRAPH:");
            writeln("src       = ", src);
            writeln("dst       = ", dst);
            writeln("srcR      = ", srcR); 
            writeln("dstR      = ", dstR);
            writeln("nei       = ", nei);
            writeln("neiR      = ", neiR);
            writeln("start_i   = ", start_i);
            writeln("start_iR  = ", start_iR);
        }
        if (!directed && weighted) {
            writeln("UNDIRECTED AND WEIGHTED GRAPH:");
            writeln("src       = ", src);
            writeln("dst       = ", dst);
            writeln("srcR      = ", srcR); 
            writeln("dstR      = ", dstR);
            writeln("nei       = ", nei);
            writeln("neiR      = ", neiR);
            writeln("start_i   = ", start_i);
            writeln("start_iR  = ", start_iR);
            writeln("e_weight  = ", weight);
            writeln("e_weightR = ", weightR);
        }
    } // end of print_graph_serverside

    /**
    * Read the graph file and store edge information in double-index data structure. 
    *
    * returns: null.
    */
    proc readLinebyLine(src: [?D1] int, dst: [?D2] int, e_weight: [?D3] real, path: string, 
                        comments: string, weighted: bool) throws {
        coforall loc in Locales  {
            on loc {
                var f = open(path, iomode.r);
                var r = f.reader(kind = ionative);
                var line:string;
                var a,b,c:string;
                var edge_count:int = 0;
                var srclocal = src.localSubdomain();
                var ewlocal = e_weight.localSubdomain();

                while r.readLine(line) {
                    // Ignore comments for all files and matrix dimensions for mtx files.
                    if (line[0] == comments) {
                        edge_count -= 1; 
                        continue;
                    } else {
                        if (edge_count < 0) {
                            edge_count = 0; 
                            continue;
                        }
                    }

                    // Parse our vertices and weights, if applicable. 
                    if (!weighted) {
                        (a,b) = line.splitMsgToTuple(2);
                    } else {
                        (a,b,c) = line.splitMsgToTuple(3);
                    }

                    // Detect a self loop and write it to the server.
                    if ((a == b) && (debug_print == true)) {
                        smLogger.error(getModuleName(),getRoutineName(),getLineNumber(),
                                        "self loop " + a + "->" + b);
                    }

                    // Place the read edge into the current locale.
                    if (srclocal.contains(edge_count)) {
                        src[edge_count] = (a:int);
                        dst[edge_count] = (b:int);

                        if (weighted) {
                            e_weight[edge_count] = (c:real);
                        }
                    }

                    edge_count += 1;

                    // Do not to write on an out of bounds locale. 
                    if (edge_count > srclocal.highBound) {
                        break;
                    }
                } 
                if (edge_count <= srclocal.highBound) {
                    var myoutMsg = "The input file does not contain enough edges for locale " 
                                    + here.id:string + " current line = " + edge_count:string;
                    smLogger.error(getModuleName(),getRoutineName(),getLineNumber(),myoutMsg);
                }
                r.close();
                f.close();
            }// end on loc
        }//end coforall
    }//end readLinebyLine

    /**
    * Write graph arrays to a file. 
    *
    * returns: null.
    */
    proc writeGraphArrays(G: borrowed SegGraph, filename: string) throws {
        // Create and open an output file with the specified filename in write mode.
        var outfile = open(filename, iomode.cw);
        var writer = outfile.writer();

        for comp in Component {
            if G.hasComp(comp) {
                var X = toSymEntry(G.getComp(comp), int).a;
                var n = X.size;
                writer.writeln(n, " ", comp:string);
                writer.writeln(X);
            }
        }
        writer.close();
        outfile.close();
    }

    /**
    * Read graph arrays from a file. 
    *
    * returns: a SegGraph.
    */
    proc readGraphArrays(G: borrowed SegGraph, filename: string) throws {
        // Open an input file with the specified filename in read mode.
        var infile = open(filename, iomode.r);
        var reader = infile.reader(kind = ionative);

        var count = 0;
        var arr_type:string;
        var line:string;
        while reader.readLine(line) {
            count += 1; 

            if (count % 2 != 0) {
                var line_split = line.split();
                arr_type = line_split[1];
                continue;
            } else {
                var X = line.split():int;
                G.withComp(new shared SymEntry(X):GenSymEntry, arr_type:Component);

                if (arr_type == "SRC") {
                    G.n_edges = X.size;
                }
                if (arr_type == "NEIGHBOR") {
                    G.n_vertices = X.size;
                }
                if (arr_type == "SRC_R") {
                    G.directed = false;
                }
                if (arr_type == "EDGE_WEIGHT") {
                    G.directed = true;
                }
            }
        }
        reader.close();
        infile.close();
    }
}