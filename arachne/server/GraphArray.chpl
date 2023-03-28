module GraphArray {
    // Chapel modules.
    use Map;
    use Reflection;
    use Utils;
    
    // Arkouda modules.
    use Logging;
    use MultiTypeSymEntry;
    use MultiTypeSymbolTable;

    // Server message logger.
    private config const logLevel = LogLevel.DEBUG;
    const graphLogger = new Logger(logLevel);

    /**
    * We use several arrays and integers to represent a graph.
    * Instances are ephemeral, not stored in the symbol table. Instead, attributes
    * of this class refer to symbol table entries that persist. This class is a
    * convenience for bundling those persistent objects and defining graph-relevant
    * operations.
    */
    class SegGraph {
        // Map to the hold various components of our Graph; use enum Component values as map keys
        var components = new map(Component, shared GenSymEntry, parSafe=false);

        // Total number of vertices
        var n_vertices : int;

        // Total number of edges
        var n_edges : int;

        // The graph is directed (True) or undirected (False)
        var directed : bool;

        // The graph is weighted (True) or unweighted (False)
        var weighted: bool;

        /**
        * Init the basic graph object, we'll compose the pieces using the withComp method.
        */
        proc init(num_v:int, num_e:int, directed:bool, weighted:bool) {
            this.n_vertices = num_v;
            this.n_edges = num_e;
            this.directed = directed;
            this.weighted = weighted;
        }

        proc isDirected():bool { return this.directed; }
        proc isWeighted():bool { return this.weighted; }

        proc withComp(a:shared GenSymEntry, atrname:Component):SegGraph { components.add(atrname, a); return this; }
        proc hasComp(atrname:Component):bool { return components.contains(atrname); }
        proc getComp(atrname:Component) { return components.getBorrowed(atrname); }  
    }

    /**
    * GraphSymEntry is the wrapper class around SegGraph so it may be stored in 
    * the Symbol Table (SymTab).
    */
    class GraphSymEntry:CompositeSymEntry {
        var graph: shared SegGraph;

        proc init(segGraph: shared SegGraph) {
            super.init();
            this.entryType = SymbolEntryType.CompositeSymEntry;
            assignableTypes.add(this.entryType);
            this.graph = segGraph;
        }
        override proc getSizeEstimate(): int {
            return 1;
        }
    }

    /**
     * Convenience proc to retrieve GraphSymEntry from SymTab.
     * Performs conversion from AbstractySymEntry to GraphSymEntry.
     */
    proc getGraphSymEntry(name:string, st: borrowed SymTab): borrowed GraphSymEntry throws {
        var abstractEntry:borrowed AbstractSymEntry = st.lookup(name);
        if !abstractEntry.isAssignableTo(SymbolEntryType.CompositeSymEntry) {
            var errorMsg = "Error: SymbolEntryType %s is not assignable to CompositeSymEntry".format(abstractEntry.entryType);
            graphLogger.error(getModuleName(),getRoutineName(),getLineNumber(),errorMsg);
            throw new Error(errorMsg);
        }
        return (abstractEntry: borrowed GraphSymEntry);
    }

    /**
    * Helper proc to cast AbstractSymEntry to GraphSymEntry.
    */
    proc toGraphSymEntry(entry: borrowed AbstractSymEntry): borrowed GraphSymEntry throws {
        return (entry: borrowed GraphSymEntry);
    }
}