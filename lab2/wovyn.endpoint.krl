ruleset wovyn_base {
    meta {
    }
    global {
        temperature_threshold = 75
        x = false
    }
  
    rule process_heartbeat {
      select when wovyn heartbeat where event:attrs{"genericThing"}
      pre {
        content = event:attrs.klog("attrs")
        genericThing = event:attrs{"genericThing"}
        data = genericThing{"data"}.decode()
        temperature = data{"temperature"}.decode()
      }
      fired {
          raise wovyn event "new_temperature_reading" attributes {
            "temperature" : temperature,
            "timestamp" : time:now()
          }
      }
    }

    rule find_high_temps {
        select when wovyn new_temperature_reading
        pre {
            content = event:attrs.klog("attrs")
            temperature = event:attrs{"temperature"}
            degrees = event:attrs{"temperatureF"}.decode()
            voilation = degrees > temperature_threshold
        }
        send_directive(degrees + " is the temperature")
        fired {
            raise wovyn event "threshold_violation" attributes {
                "degrees":degrees,
            } if voilation
        }
    }

    rule threshold_notification {
        select when wovyn threshold_violation
        pre {
            content = event:attrs.klog("attrs")
            degrees = event:attrs{"degrees"}
            message = "Temperature: " + degrees + " is too hot! (over " + temperature_threshold + ")" 
        }
        fired {
            raise twilio event "send_message" attributes {
                "message":message,
            }
        }
    }
  }