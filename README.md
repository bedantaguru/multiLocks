# multiLock 
##### A 'Multiple Locks' mechanism for R 
\
This is a **prototype** package (designed mainly for internal use). 

A similar package named [flock](https://github.com/ivannp/flock) (clone project [link](https://github.com/systematicinvestor/flock)) is avilable in **CRAN**.

**flock** is more general purpose and adopts file lock mechanism (possibly through OS). However, it is not designed for multiple locks. Also, it does not allow users to interrupt while seeking for the lock. The use-case is quite different here. 

It is currently based on [storr](https://github.com/richfitz/storr): Simple object cacher for R by [Rich FitzJohn](https://github.com/richfitz)

Install this package in R with `devtools::install_github` with the following call:

    devtools::install_github("MadeInR/multiLocks")
