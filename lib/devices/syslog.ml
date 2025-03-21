open Functoria.DSL
open Misc
open Stack

type syslog = SYSLOG

let syslog = typ SYSLOG
let pkg sublibs = [ package ~min:"0.5.0" ~max:"0.6.0" ~sublibs "logs-syslog" ]

let syslog_udp_conf ?group () =
  let endpoint = Runtime_arg.syslog ?group None
  and port = Runtime_arg.syslog_port ?group None
  and hostname = Runtime_arg.monitor_hostname ?group ()
  and truncate = Runtime_arg.syslog_truncate ?group None in
  let packages = pkg [ "mirage" ] in
  let runtime_args =
    Runtime_arg.[ v endpoint; v hostname; v port; v truncate ]
  in
  let connect _i modname = function
    | [ stack; endpoint; hostname; port; truncate ] ->
        code ~pos:__POS__
          "@[<v 2>match %s with@ | None ->Logs.warn (fun m -> m \"no syslog \
           server specified, dumping logs to stdout\"); Lwt.return_unit@ | \
           Some server ->@ let reporter =@ %s.create %s ~hostname:%s ~port:%s \
           server ?truncate:%s ()@ in@ Logs.set_reporter reporter;@ \
           Lwt.return_unit@]"
          endpoint modname stack hostname port truncate
    | _ -> connect_err "syslog_udp" 5
  in
  impl ~packages ~runtime_args ~connect "Logs_syslog_mirage.Udp"
    (stackv4v6 @-> syslog)

let syslog_udp ?group stack = syslog_udp_conf ?group () $ stack

let syslog_tcp_conf ?group () =
  let endpoint = Runtime_arg.syslog ?group None
  and port = Runtime_arg.syslog_port ?group None
  and hostname = Runtime_arg.monitor_hostname ?group ()
  and truncate = Runtime_arg.syslog_truncate ?group None in
  let packages = pkg [ "mirage" ] in
  let runtime_args =
    Runtime_arg.[ v endpoint; v hostname; v port; v truncate ]
  in
  let connect _i modname = function
    | [ stack; endpoint; hostname; port; truncate ] ->
        code ~pos:__POS__
          "@[<v 2>match %s with@ | None -> Logs.warn (fun m -> m \"no syslog \
           server specified, dumping logs to stdout\"); Lwt.return_unit@ | \
           Some server ->@ %s.create %s ~hostname:%s ~port:%s server \
           ?truncate:%s () >>= function@ | Ok reporter -> Logs.set_reporter \
           reporter; Lwt.return_unit@ | Error e -> invalid_arg e@]"
          endpoint modname stack hostname port truncate
    | _ -> connect_err "syslog_tcp" 5
  in
  impl ~packages ~runtime_args ~connect "Logs_syslog_mirage.Tcp"
    (stackv4v6 @-> syslog)

let syslog_tcp ?group stack = syslog_tcp_conf ?group () $ stack

let syslog_tls_conf ?group () =
  let endpoint = Runtime_arg.syslog ?group None
  and port = Runtime_arg.syslog_port ?group None
  and hostname = Runtime_arg.monitor_hostname ?group ()
  and truncate = Runtime_arg.syslog_truncate ?group None
  and keyname = Runtime_arg.syslog_keyname ?group None in
  let packages = pkg [ "mirage"; "mirage.tls" ] in
  let runtime_args =
    Runtime_arg.[ v endpoint; v hostname; v port; v truncate; v keyname ]
  in
  let connect _i modname = function
    | [ stack; kv; endpoint; hostname; port; truncate; keyname ] ->
        code ~pos:__POS__
          "@[<v 2>match %s with@ | None -> Logs.warn (fun m -> m \"no syslog \
           server specified, dumping logs to stdout\"); Lwt.return_unit@ | \
           Some server ->@ %s.create %s %s ~hostname:%s ~port:%s server \
           ?truncate:%s ?keyname:%s () >>= function@ | Ok reporter -> \
           Logs.set_reporter reporter; Lwt.return_unit@ | Error e -> \
           invalid_arg e@]"
          endpoint modname stack kv hostname port truncate keyname
    | _ -> connect_err "syslog_tls" 8
  in
  impl ~packages ~runtime_args ~connect "Logs_syslog_mirage_tls.Tls"
    (stackv4v6 @-> Kv.ro @-> syslog)

let syslog_tls ?group stack kv = syslog_tls_conf ?group () $ stack $ kv

let monitoring_conf ?group () =
  let monitor_host = Runtime_arg.monitor ?group None
  and hostname = Runtime_arg.monitor_hostname ?group () in
  let packages = [ package ~min:"0.0.6" ~max:"0.1.0" "mirage-monitoring" ] in
  let runtime_args = Runtime_arg.[ v monitor_host; v hostname ] in
  let connect _i modname = function
    | [ stack; name; monitor ] ->
        code ~pos:__POS__
          "Lwt.return (match %s with| None -> Logs.warn (fun m -> m \"no \
           monitor specified, not outputting statistics\")| Some ip -> \
           %s.create ip ~hostname:%s %s)"
          monitor modname name stack
    | _ -> assert false
  in
  impl ~packages ~runtime_args ~connect "Mirage_monitoring.Make"
    (stackv4v6 @-> Functoria.job)

let monitoring ?group stack = monitoring_conf ?group () $ stack
