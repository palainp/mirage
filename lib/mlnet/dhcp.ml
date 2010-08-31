(*
 * Copyright (c) 2006-2010 Anil Madhavapeddy <anil@recoil.org>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 *)

open Lwt
open Printf
open Mlnet_types

module Client(IP:Ipv4.UP)(UDP:Udp.UP) = struct

  type offer = {
    ip_addr: ipv4_addr;
    netmask: ipv4_addr option;
    gateways: ipv4_addr list;
    dns: ipv4_addr list;
    lease: int32;
    xid: int32;
  }

  type state = 
  | Request_sent of int32
  | Offer_accepted of offer
  | Lease_held of offer

  type t = {
    udp: UDP.t;
    ip: IP.t;
    mutable state: state;
  }

  (* Send a client broadcast packet *)
  let output_broadcast t ~xid ~yiaddr ~siaddr ~options =
    (* DHCP pads the MAC address to 16 bytes *)
    let chaddr = `Str ((ethernet_mac_to_bytes (IP.mac t.ip)) ^ 
      (String.make 10 '\000')) in

    let options = `Str (Dhcp_option.Packet.to_bytes options) in

    let dhcpfn env =
      ignore(Mpl.Dhcp.t
        ~op:`BootRequest ~xid ~secs:10 ~broadcast:0
        ~ciaddr:0l ~yiaddr:(ipv4_addr_to_uint32 yiaddr) 
        ~siaddr:(ipv4_addr_to_uint32 siaddr)
        ~giaddr:0l ~chaddr
        ~sname:(`Str (String.make 64 '\000'))
        ~file:(`Str (String.make 128 '\000'))
        ~options env)
    in
    let dest_ip = ipv4_broadcast in
    let udpfn env = 
      ignore(Mpl.Udp.t
        ~source_port:68 ~dest_port:67
        ~checksum:0
        ~data:(`Sub dhcpfn) env)
    in
    UDP.output t.udp ~dest_ip udpfn

   (* Receive a DHCP UDP packet *)
  let input t (ip:Mpl.Ipv4.o) (udp:Mpl.Udp.o) =
    let dhcp = Mpl.Dhcp.unmarshal udp#data_env in 
    let packet = Dhcp_option.Packet.of_bytes dhcp#options in
    (* See what state our Netif is in and if this packet is useful *)
    Dhcp_option.Packet.(match t.state with
    | Request_sent xid -> begin
        (* we are expecting an offer *)
        match packet.op, dhcp#xid with 
        |`Offer, offer_xid when offer_xid=xid ->  begin
            let ip_addr = ipv4_addr_of_uint32 dhcp#yiaddr in
            printf "DHCP: offer received: %s\n%!" (ipv4_addr_to_string ip_addr);
            let netmask = find packet
              (function `Subnet_mask addr -> Some addr |_ -> None) in
            let gateways = findl packet 
              (function `Router addrs -> Some addrs |_ -> None) in
            let dns = findl packet 
              (function `DNS_server addrs -> Some addrs |_ -> None) in
            let lease = 0l in
            let offer = { ip_addr; netmask; gateways; dns; lease; xid } in
            let yiaddr = ipv4_addr_of_uint32 dhcp#yiaddr in
            let siaddr = ipv4_addr_of_uint32 dhcp#siaddr in
            let options = { op=`Request; opts= [
                `Requested_ip ip_addr;
                `Server_identifier siaddr;
              ] } in
            output_broadcast t ~xid ~yiaddr ~siaddr ~options >>
            (t.state <- Offer_accepted offer;
            return ())
        end
        |_ -> Printf.printf "DHCP: offer not for us"; return ()
    end
    | Offer_accepted info -> begin
        (* we are expecting an ACK *)
        match packet.op, dhcp#xid with 
        |`Ack, ack_xid when ack_xid = info.xid -> begin
            let lease =
              match find packet (function `Lease_time lt -> Some lt |_ -> None) with
              | None -> 300l (* Just leg it and assume a lease time of 5 minutes *)
              | Some x -> x in
            let info = { info with lease=lease } in
            (* TODO also merge in additional requested options here *)
            t.state <- Lease_held info;
            IP.set_ip t.ip info.ip_addr >>
            (match info.netmask with 
             | Some x -> IP.set_netmask t.ip x 
             | None -> return ()) >>
            return ()
       end
       |_ -> printf "DHCP: ack not for us\n%!"; return ()
    end
    |_ -> printf "DHCP: unknown DHCP state\n%!"; return ()
  )
 
  (* Start a DHCP discovery off on an interface *)
  let start_discovery t =
    let xid = Random.int32 Int32.max_int in
    let yiaddr = ipv4_blank in
    let siaddr = ipv4_blank in
    let options = { Dhcp_option.Packet.op=`Discover; opts= [
       (`Parameter_request [`Subnet_mask; `Router; `DNS_server; `Broadcast]);
       (`Host_name "miragevm")
     ] } in
    output_broadcast t ~xid ~yiaddr ~siaddr ~options >>
    (t.state <- Request_sent xid;
    return ())

end
