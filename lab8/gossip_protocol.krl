ruleset gossip_protocol {
    meta {
        shares get_peer_logs, get_seen_messages, get_connections, get_scheduled_events, remove_scheduled_event
    }

    global {
        get_scheduled_events = function() {
            schedule:list()
        }

        remove_scheduled_event = function(id) {
            schedule:remove(id)
        }

        get_peer_logs = function() {
            ent:peer_logs
        }

        get_seen_messages = function() {
            ent:stored_messages
        }

        get_connections = function() {
            ent:peer_connections
        }

        parse_message = function(MessageID, part) {
            MessageID.split(":")[part]
        }

        find_missing = function(known_logs, received_logs) {
            known_logs.difference(received_logs)
        }
    }

    rule handle_seen {
        select when gossip seen
        pre {
            received_logs = event:attrs{"logs"}
            missing_messages = find_missing(ent:peer_logs{ent:sensor_id}, received_logs).klog("Missing messages...")
        }
        always {
            raise gossip event "handle_missing" attributes {
                "messages" : missing_messages
            } if missing_messages.length() > 0
        }
    }

    
    rule send_seen {
        select when gossip send_seen
        pre {
            Peer_ID = event:attrs{"Id"}
            Peer_TX = get_connections(){[Peer_ID, "Tx"]}
            logs_to_send = ent:peer_logs{ent:sensor_id}.klog("Sending known logs...")
        }
        event:send({
            "eci": Peer_TX,
            "domain": "gossip", "name":"seen",
            "attrs": {
                "logs": logs_to_send
            }
        })
    }

    rule handle_rumor {
        select when gossip rumor 
        pre {
            Message = event:attrs{"Message"}
            message_id_full = Message{"MessageID"}
            message_id = parse_message(message_id_full, 0)
            sequence_num = parse_message(message_id_full, 1)
            sensor_id = Message{"SensorID"}
            next_message_in_sequence = (ent:peer_logs{[sensor_id, sensor_id]}.defaultsTo(-1) + 1) == sequence_num.as("Number")
            known_message = ent:stored_messages{[sensor_id, "MessageID"]} >< message_id_full && (ent:peer_logs{[sensor_id, sensor_id]}.defaultsTo(-1)) >= sequence_num.as("Number")
        }
        always {
            ent:stored_messages{sensor_id} := ent:stored_messages{sensor_id}.defaultsTo([]).append(Message) if not known_message
            ent:peer_logs{[sensor_id, sensor_id]} := (ent:peer_logs{[sensor_id, sensor_id]}.defaultsTo(-1) + 1) if next_message_in_sequence
        }
    }

    rule catch_heartbeat {
        select when gossip heartbeat
        send_directive("Heartbeat event received")

        //TODO: Pick someone to send it to and send it to them
    }

    rule handle_heartbeat {
        select when gossip create_message
        pre {
            Peer_ID = event:attrs{"Id"}
            Peer_TX = get_connections(){[Peer_ID, "Tx"]}
            MessageID = ent:sensor_id + ":" + ent:sequence_num
            SensorID = ent:sensor_id
            Temperature = ent:temperature
            Timestamp = ent:timestamp
            Message = {}.put("MessageID", MessageID).put("SensorID", SensorID).put("Temperature", Temperature).put("Timestamp", Timestamp)
        }
        event:send({
            "eci": Peer_TX,
            "domain": "gossip", "name":"rumor",
            "attrs": {
                "Message": Message
            }
        })
        fired {
            ent:peer_logs{[Peer_ID, ent:sensor_id]} := ent:sequence_num
            ent:peer_logs{[ent:sensor_id, ent:sensor_id]} := ent:sensor_id
            ent:sequence_num := ent:sequence_num + 1
            ent:stored_messages{ent:sensor_id} := ent:stored_messages{ent:sensor_id}.defaultsTo([]).append(Message)
        }
    }

    rule add_peer {
        select when gossip add_peer
        pre {
            ID = event:attrs{"ID"}
            Tx = event:attrs{"Tx"}
        }
        always {
            ent:peer_connections{ID} := {}.put("ID", ID).put("Tx", Tx)
        }
    }

    rule reset_gossip {
        select when gossip reset
        foreach ent:peer_connections setting (peer)
        always {
            ent:peer_logs{peer{"ID"}} := {}
        }
    }

    rule reset_stored {
        select when gossip reset
        always {
            ent:stored_messages := {}
            ent:sequence_num := 0
        }
    }

    rule schedule_gossip {
        select when gossip scheduler
        pre {
            period = event:attrs{"period"} || 10
        }
        always {
            schedule gossip event "heartbeat"
                repeat << */#{period} * * * * * >>
        }
    }

    rule collect_recent_temperature {
        select when wovyn new_temperature_reading
        pre {
            passed_temp = event:attrs{"temperature"}
            passed_timestamp = event:attrs{"timestamp"}
        }
        always {
            ent:timestamp := passed_timestamp
            ent:temperature := passed_temp
        }
    }

    rule process_heartbeat {
        select when wovyn heartbeat
  
        pre {
          genericThing = event:attrs{"genericThing"}
          data = genericThing{"data"}
          temperature = data{"temperature"}
          degrees = temperature[0]{"temperatureF"}
        }
  
        fired {        
          raise wovyn event "new_temperature_reading" attributes {
              "temperature" : degrees,
              "timestamp" : time:now()
          } if genericThing != null
        }
      }
  

    rule initialize_sensors {
        select when wrangler ruleset_installed where event:attrs{"rids"} >< meta:rid
        fired {
            ent:sensor_id := meta:eci
            ent:sequence_num := 0
        }
    }
}

//1
//cl1778cic00cd1sbz9eulb8is id
//cl177f6uq00nh1sbzbgwcbf02 tx

//2
//cl1778ada00bg1sbz2hux0l7p id
//cl177f6uu00nj1sbz0r22dij6 tx