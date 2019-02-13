
#' Multiple locks
#'
#' @param path A local filesystem path where lock will be created
#' @param allowed_number_of_jobs Maximum number of jobs (tasks or processes) which is possible to run concurrently. The default is 1 (unless any process initiated more than that)
#' @param id An identifier for uniquely pointing the lock (optional parameter).
#' @param fresh Default is \code{FALSE}. If \code{TRUE} the directory (as specified by path) will be cleaned and recreated so that earlier locks will not interfere.
#'
#' @return An access handle (environment) with lock, unlock and destroy method. All are empty argument functions.
#' \code{lock} will try to lock the current process.
#' \code{unlock} will unlock the current process.
#' \code{destroy} will delete the lock folder. (Potentially this should be called by only one process at the end of operations)
#' @export
#'
#' @examples
#'
multi_lock  <- function(path, allowed_number_of_jobs, id, fresh = F){

  st <- storr::storr_rds(path)

  if(fresh){
    st$destroy()
    st <- storr::storr_rds(path)
  }

  if(st$exists("allowed_number_of_jobs","info")){
    if(!missing(allowed_number_of_jobs)){
      if(allowed_number_of_jobs != as.integer(st$get("allowed_number_of_jobs","info") )){
        stop("allowed_number_of_jobs mismatch")
      }
    }else{
      allowed_number_of_jobs <- as.integer(st$get("allowed_number_of_jobs","info") )
    }
  }else{
    if(missing(allowed_number_of_jobs)){
      allowed_number_of_jobs <- 1
    }
  }

  if(st$exists("id","info")){
    if(!missing(id)){
      if(id != as.character(st$get("id","info") )){
        stop("id mismatch")
      }
    }else{
      id <- as.character(st$get("id","info") )
    }
  }else{
    if(missing(id)){
      id <- "default"
    }
  }


  st$set("allowed_number_of_jobs", allowed_number_of_jobs, "info")
  st$set("id", id, "info")

  # returns T if locked elase F
  lock_raw <- function(){
    # process which are trying to lock
    if(st$exists(Sys.getpid(), "lock_stage_2")){
      # already locked
      return(T)
    }

    if(!st$exists(Sys.getpid(), "lock_stage_1")){
      # first time logging (wished already to lock / waiting to lock)
      if(length(st$list("lock_stage_1"))<allowed_number_of_jobs){
        st$set(Sys.getpid(), 1, "lock_stage_1")
        st$del(Sys.getpid(), "wait_at_stage_1")
      }else{
        st$set(Sys.getpid(), 1, "wait_at_stage_1")
        return(F)
      }
      Sys.sleep(0.2)

    }


    if(!st$exists(Sys.getpid(), "lock_stage_2")){
      if(length(st$list("lock_stage_1"))<=allowed_number_of_jobs & length(st$list("lock_stage_2"))<allowed_number_of_jobs){
        # namespace for actual locks
        st$set(Sys.getpid(), 1, "lock_stage_2")
        st$del(Sys.getpid(), "wait_at_stage_2")
      }else{
        st$set(Sys.getpid(), 1, "wait_at_stage_2")
        return(F)
      }
    }


    st$exists(Sys.getpid(), "lock_stage_2")

  }

  unlock_raw <- function(){
    if(st$exists(Sys.getpid(), "lock_stage_2")){
      st$del(Sys.getpid(), "lock_stage_2")
      st$del(Sys.getpid(), "lock_stage_1")
    }

    # delete from any other places (if left wrongly)
    st$del(Sys.getpid(), "wait_at_stage_1")
    st$del(Sys.getpid(), "wait_at_stage_2")
  }

  # dummy initialization
  active_pids <- Sys.getpid()

  check_pid <- function(pids){
    pids %in% active_pids
  }

  clean_ns <- function(ns){

    pids <- st$list(ns)
    dead_pids <- pids[!check_pid(pids)]

    if(length(dead_pids)){
      lapply(dead_pids, st$del, namespace = ns)
    }

  }

  clean_deads <- function(){
    active_pids <<- ps::ps()$pid
    clean_ns("lock_stage_1")
    clean_ns("lock_stage_2")
    clean_ns("wait_at_stage_1")
    clean_ns("wait_at_stage_2")
  }

  waiting_queue_resolver <- function(){
    active_locks <- st$list("lock_stage_2")
    waiting_locks <- st$list("wait_at_stage_2")
    if(length(active_locks)<allowed_number_of_jobs & length(waiting_locks)>0){
      if(!st$exists("waiting_queue_resolver","resolver")){
        # no body yet initiated for waiting_queue_resolver
        if(length(st$list("willing_waiting_queue_resolver"))<allowed_number_of_jobs){

          # express to resolve waiting_queue
          st$set(Sys.getpid(), 1, "willing_waiting_queue_resolver")

          while(length(st$list("willing_waiting_queue_resolver"))<allowed_number_of_jobs){
            # wait for sufficient willing candidate
            Sys.sleep(0.1)
          }

          elected_waiting_queue_resolver <- max(st$list("willing_waiting_queue_resolver"))

          if(Sys.getpid()==elected_waiting_queue_resolver){
            # lock waiting_queue_resolver
            st$set("waiting_queue_resolver", elected_waiting_queue_resolver, "resolver")
            st$clear("willing_waiting_queue_resolver")

            rest_allowed <- allowed_number_of_jobs-length(active_locks)
            port_to_allowed <- waiting_locks[seq(min(rest_allowed, length(waiting_locks)))]
            st$mset(port_to_allowed, 1, "lock_stage_2")

            lapply(st$list("lock_stage_2"), st$del, namespace = "wait_at_stage_2")

            st$del("waiting_queue_resolver", "resolver")

          }

        }
      }

    }
  }

  l <- new.env()

  l$lock <- function(){
    it <- 0
    while(!lock_raw()){
      waiting_queue_resolver()
      it <- it +1
      if(it > 100){
        clean_deads()
        it <- 0
      }
    }
  }

  l$unlock <- function(){
    unlock_raw()
    waiting_queue_resolver()
  }

  l$destroy <- function(){
    st$destroy()
  }

  return(l)

}


