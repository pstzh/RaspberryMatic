#!/bin/tclsh

# DutyCycle Script v.2.2 developed by Andreas B�nting (HMside)
# Dieses Script liest den DutyCycle Status der HomeMatic CCU und Gateways aus
# und erstellt automatisch eine Systemvariable vom Typ Zahl mit dem Gateway Namen bzw. alternativ mit der Ger�te-Seriennummer.
# Wird der Gateway Name nachtr�glich gesetzt, wird die zuvor erstellte Systemvariable automatisch umbenannt.
# Zudem wird eine DutyCycle System-Log Meldung erzeugt und f�r den Support eine Datei mit dem DC-Status im User-Verzeichnis angelegt.
# F�r den HM-CFG-LAN wird der DutyCycle Status bei einer Verbindungsunterbrechung auf -1 gesetzt.

load tclrpc.so
load tclrega.so

set CONFIG_FILE {/usr/local/etc/config/rfd.conf}
set gateways [xmlrpc http://127.0.0.1:2001/ listBidcosInterfaces]
#puts $gateways

# DC-File anlegen um den DutyCycle Status f�r den Support anhand eines Backups sichtbar zu machen
#close [open /usr/local/etc/config/dc "w"]
#set date [clock seconds]
#set date [clock format $date -format {%d.%m.%Y %T}]

# Gateway Konfiguration aus rfd.conf einlesen
array set config {}
array set section {}
set sectionName {}

catch {
  set fd [open $CONFIG_FILE r]
  catch {
    while { ![eof $fd] } {
      set line [string trimleft [gets $fd]]
      if { "\#" != [string index $line 0] } then {
        if { [regexp {\[([^\]]+)\]} $line dummy newSectionName] } then {
          set config($sectionName) [array get section]
          set sectionName $newSectionName
        }
        if { [regexp {([^=]+)=(.+)} $line dummy name value] } then {
          set section([string trim $name]) [string trim $value]
        }
      }
    }
    set config($sectionName) [array get section]
  }
  close $fd
}

# Zentralen und Gateway DutyCycle sowie weitere Infos abfragen
set lines [split [string map [list "{AD" "\x00"] $gateways] "\x00"]

regsub -all "]" $lines "" lines
regsub -all "{" $lines "" lines
regsub -all "}" $lines "" lines

set ccuoben ""
set gwoben ""
set interfaces {}
set gwname {}

foreach line $lines {
  set snoben ""
  set dutycycle ""
  set type ""
  set type1 ""

  regexp "DRESS (.*?) " $line dummy snoben
  regexp "CONNECTED (.*?) " $line dummy connection
  regexp "DUTY_CYCLE (.*?) " $line dummy dutycycle
  regexp "FIRMWARE_VERSION (.*?) " $line dummy fw
  regexp "TYPE (.+)" $line dummy type
  regsub -all {\\} $type "" type1
  regsub -all " " $type1 "" type2

  if {$type2 == "CCU2"} {
    set ccuoben $snoben
    set ccutype "DutyCycle"
    puts "--------------------"
    puts $ccuoben
    puts "$connection / $dutycycle"
    puts "$ccutype / $fw"
    # Pr�fen ob DC Systemvariable f�r CCU2 existiert und ggf. anlegen
    append rega_cmd_create_sv "string svName ='$ccutype';object svObj = dom.GetObject(svName);if (!svObj){object svObjects = dom.GetObject(ID_SYSTEM_VARIABLES);svObj = dom.CreateObject(OT_VARDP);svObjects.Add(svObj.ID());svObj.Name(svName);svObj.ValueType(ivtFloat);svObj.ValueSubType(istGeneric);svObj.DPInfo('DutyCycle CCU');svObj.ValueUnit('%');svObj.ValueMin(-100);svObj.ValueMax(100);svObj.State(0);svObj.Internal(false);svObj.Visible(true);dom.RTUpdate(true);}"
    rega_script $rega_cmd_create_sv
    # CCU DutyCycle Variable aktualisieren
    append rega_cmd "dom.GetObject(ID_SYSTEM_VARIABLES).Get('$ccutype').State('$dutycycle');"
    rega_script $rega_cmd
    # CCU DutyCycle System-Log Meldung erzeugen
    exec logger -t dutycycle -p info "$ccutype-CCU / FW: $fw / DC: $dutycycle %"
    # Datum/Uhrzeit und CCU DutyCycle in DC-File schreiben
    #exec echo "$date" >> /usr/local/etc/config/dc
    #exec echo "$ccuoben=$dutycycle\nCONNECTED=$connection\nFIRMWARE=$fw" >> /usr/local/etc/config/dc
    } else {
      # Sektion f�r Gateways
      set gwoben $snoben
      puts "--------------------"
      puts "$connection / $dutycycle"
      puts "$gwoben / $fw"

      foreach sectionName [array names config] {
        array set section $config($sectionName)
        set sn [array get section {Serial Number}]
        set sn1 $section(Serial Number)
        if { $sn1 == $gwoben } then {
          array set interface {}
          set interface(userName)      [array get section {Name}]
          lappend interfaces [array get interface]
          set gwname $section(Name)
          set gwname1 "DutyCycle-$gwname"
          set gwnoname "DutyCycle-$sn1"
          # Wenn kein Gateway Name eingetragen wurde, wird als Variablenname "DutyCycle-Seriennummer" gesetzt
          if { $gwname == "" } then {
            puts $gwnoname
            # Wenn HM-CFG-LAN disconnected dann DC -1 setzen
            if {($type2 == "LanInterface") && ($connection == "0" )} then {
              set dutycycle -1
            }
            # Pr�fen ob DC Systemvariable f�r Gateways existieren und ggf. anlegen
            append rega_cmd_create_sv "string svName = '$gwnoname';object svObj = dom.GetObject(svName);if (!svObj){object svObjects = dom.GetObject(ID_SYSTEM_VARIABLES);svObj = dom.CreateObject(OT_VARDP);svObjects.Add(svObj.ID());svObj.Name(svName);svObj.ValueType(ivtFloat);svObj.ValueSubType(istGeneric);svObj.DPInfo('DutyCycle Gateway');svObj.ValueUnit('%');svObj.ValueMin(-100);svObj.ValueMax(100);svObj.State(0);svObj.Internal(false);svObj.Visible(true);dom.RTUpdate(true);}"
            rega_script $rega_cmd_create_sv
            # DutyCycle Variable aktualisieren
            append rega_cmd "dom.GetObject(ID_SYSTEM_VARIABLES).Get('$gwnoname').State('$dutycycle');"
            rega_script $rega_cmd
            # DutyCycle System-Log Meldung erzeugen
            exec logger -t dutycycle -p info "$gwnoname / FW: $fw / DC: $dutycycle %"
            # DutyCycle in DC-File schreiben
            #exec echo "$sn1=$dutycycle$\nCONNECTED=$connection\nFIRMWARE=$fw" >> /usr/local/etc/config/dc
            } else {
              puts $gwname1
              if {($type2 == "LanInterface") && ($connection == "0" )} then {
                set dutycycle -1
                #puts "$type2 nicht verbunden DC=$dutycycle"
              }
              # Wird der Gateway Name nachtr�glich gesetzt, Systemvariable mit Seriennummer umbenennen
              append rega_cmd_rename_sv "string svName = '$gwnoname';string svNewName = '$gwname1';object svObj = dom.GetObject(svName);if (svObj){dom.GetObject(svName).Name(svNewName);dom.RTUpdate(true)};"
              rega_script $rega_cmd_rename_sv
              # Wenn ein Gateway Name eingetragen wurde, wird dieser angehangen z.B. "DutyCycle-OG1"
              append rega_cmd_create_sv "string svName = '$gwname1';object svObj  = dom.GetObject(svName);if (!svObj){object svObjects = dom.GetObject(ID_SYSTEM_VARIABLES);svObj = dom.CreateObject(OT_VARDP);svObjects.Add(svObj.ID());svObj.Name(svName);svObj.ValueType(ivtFloat);svObj.ValueSubType(istGeneric);svObj.DPInfo('DutyCycle Gateway');svObj.ValueUnit('%');svObj.ValueMin(-100);svObj.ValueMax(100);svObj.State(0);svObj.Internal(false);svObj.Visible(true);dom.RTUpdate(true);}"
              rega_script $rega_cmd_create_sv
              # DutyCycle Variable aktualisieren
              append rega_cmd "dom.GetObject(ID_SYSTEM_VARIABLES).Get('$gwname1').State('$dutycycle');"
              rega_script $rega_cmd
              # DutyCycle System-Log Meldung erzeugen
              exec logger -t dutycycle -p info "$gwname1 / FW: $fw / DC: $dutycycle %"
              # DutyCycle in DC-File schreiben
              #exec echo "$sn1=$dutycycle\nCONNECTED=$connection\nFIRMWARE=$fw" >> /usr/local/etc/config/dc
            }
        }
      }
    }
  }
