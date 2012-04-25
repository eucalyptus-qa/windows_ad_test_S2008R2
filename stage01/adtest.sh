#!/bin/bash

source ../lib/winqa_util.sh
setup_euca2ools;

cp ../etc/id_rsa.proxy ./
chmod 400 ./id_rsa.proxy                                                                                                        

if [ $(get_networkmode) = "SYSTEM"  ]; then
      echo "NETWORK MODE is system"
      sleep 10
      exit 0
fi

hostbit=$(host_bitness)
guestbit=$(guest_bitness)
if [ $guestbit -eq "64" ] && [ $hostbit -eq "32" ]; then
    echo "Running 64 bit guest on 32 bit host"
    sleep 10
    exit 0
fi
                                                                                    
winimgs=$(euca-describe-images | grep windows | grep -v deregistered)
if [ -z "$winimgs" ]; then
        echo "ERROR: No windows image is found in Walrus"
        exit 1
fi

hypervisor=$(describe_hypervisor)
echo "Hypervisor: $hypervisor"

exitCode=0
IFS=$'\n'
for img in $winimgs; do
	if [ -z "$img" ]; then
		continue;
	fi
	IFS=$'\n'
        emi=$(echo $img | cut -f2)
	echo "EMI: $emi"

	unset IFS
   	ret=$(euca-describe-instances | grep $emi | grep -E "running")
	if [ -z "$ret" ]; then
		echo "ERROR: Can't find the running instance of $emi"
		exitCode=1
		break;
	fi
        instance=$(echo -e ${ret/*INSTANCE/} | cut -f1 -d ' ')
	if [ -z $instance ]; then
                echo "ERROR: Instance from $emi is null"
		exitCode=1
                break;
        fi
	zone=$(echo -e ${ret/*INSTANCE/} | cut -f10 -d ' ')
        ipaddr=$(echo -e ${ret/*INSTANCE/} | cut -f3 -d ' ')
	keyname=$(echo -e ${ret/*INSTANCE/} | cut -f6 -d ' ')
	
	if [ -z "$zone" ] || [ -z "$ipaddr" ] || [ -z "$keyname" ]; then
		echo "ERROR: Parameter is missing: zone=$zone, ipaddr=$ipaddr, keyname=$keyname"
		exitCode=1
		break;
	fi
        keyfile_src=$(whereis_keyfile $keyname)
        if ! ls -la $keyfile_src; then
            echo "ERROR: cannot find the key file from $keyfile_src"
            exitCode=1
            break
        fi
      
	keyfile="$keyname.priv"

        cp $keyfile_src $keyfile
	
	if [ ! -s $keyfile ]; then
		echo "ERROR: can't find the key file $keyfile";
		exitCode=1
		break;
	fi

        cmd="euca-get-password -k $keyfile $instance"
        echo $cmd
        passwd=$($cmd)
        if [ -z "$passwd" ]; then
                 echo "ERROR: password is null"; 
                 exitCode=1
                 break;
        fi

       if ! should_test_guest; then
                echo "[WARNING] We don't perform guest test for this instance";
                sleep 10;
                continue;
        fi

        ret=$(./login.sh -h $ipaddr -p $passwd)
        if [ -z "$(echo $ret | tail -n 1 | grep 'SUCCESS')" ]; then
               echo "ERROR: Couldn't login ($ret)";
               exitCode=1
               break;
        fi

        ret=$(./admembership.sh)
        if [ -z "$ret" ]; then
                 echo "ERROR: AD membership test"
                 exitCode=1
                 ret=$(./eucalog.sh)
                 echo "WINDOWS INSTANCE LOG: $ret"
                 break;
        else    
                 echo "Passed AD membership test; domain: $ret"
        fi      
                
       ret=$(./adkeytest.sh)
        if [ -z "$(echo $ret | tail -n 1 | grep 'SUCCESS')" ]; then
                echo "ERROR: AD key test ($ret)";
                exitCode=1
               ret=$(./eucalog.sh)
               echo "WINDOWS INSTANCE LOG: $ret"
         else    
                echo "passed adkey test"     
        fi      
                
        ret=$(./rdpermission.sh)
        if [ -z "$(echo $ret | tail -n 1 | grep 'SUCCESS')" ]; then
                echo "ERROR: Remote desktop permission test ($ret)";
                exitCode=1
                ret=$(./eucalog.sh)
                echo "WINDOWS INSTANCE LOG: $ret"
        else    
                echo "passed Remote desktop permission test"     
        fi      

	if [ $exitCode -eq 0 ]; then
		echo "Active Directory test passed for $instance";
	else
		break;
	fi
done
exit "$exitCode"

