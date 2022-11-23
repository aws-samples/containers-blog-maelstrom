echo "This tool validates the Amazon EKS optimized AMI against CIS Bottlerocket Benchmark v1.0.0"

Num_Of_Checks_Passed=0
Total_Num_Of_Checks=10

function checkSysctlConfig()
{
    for str in ${sysctlList[@]}; do
       v1=$(sysctl $str | awk '{print $3}' )
       if [[ "$v1" != $expectedValue ]] 
       then
        return 0
       fi
    done
    return 1
}

RECOMMENDATION="3.1.1 Ensure packet redirect sending is disabled (Automated)"
sysctlList=("net.ipv4.conf.all.send_redirects" "net.ipv4.conf.default.send_redirects")
expectedValue=0
checkSysctlConfig


if [ "$?" -eq "1" ]; then
  >&2 echo "[PASS] $RECOMMENDATION"
    Num_Of_Checks_Passed=$((Num_Of_Checks_Passed+1))
else
  >&2 echo "[FAIL] $RECOMMENDATION"
fi

RECOMMENDATION="3.2.2 Ensure ICMP redirects are not accepted (Automated)"
sysctlList=("net.ipv4.conf.all.accept_redirects" "net.ipv4.conf.default.accept_redirects" "net.ipv6.conf.all.accept_redirects" "net.ipv6.conf.default.accept_redirects")
expectedValue=0
checkSysctlConfig


if [ "$?" -eq "1" ]; then
    echo "[PASS] $RECOMMENDATION"
    Num_Of_Checks_Passed=$((Num_Of_Checks_Passed+1))
else
    echo "[FAIL] $RECOMMENDATION"
fi

RECOMMENDATION="3.2.3 Ensure secure ICMP redirects are not accepted (Automated)"
sysctlList=("net.ipv4.conf.all.secure_redirects" "net.ipv4.conf.default.secure_redirects")
expectedValue=0
checkSysctlConfig


if [ "$?" -eq "1" ]; then
    echo "[PASS] $RECOMMENDATION"
    Num_Of_Checks_Passed=$((Num_Of_Checks_Passed+1))
else
    echo "[FAIL] $RECOMMENDATION"
fi

RECOMMENDATION="3.2.4 Ensure suspicious packets are logged (Automated)"
sysctlList=("net.ipv4.conf.all.log_martians" "net.ipv4.conf.default.log_martians")
expectedValue=1
checkSysctlConfig


if [ "$?" -eq "1" ]; then
    echo "[PASS] $RECOMMENDATION"
    Num_Of_Checks_Passed=$((Num_Of_Checks_Passed+1))
else
    echo "[FAIL] $RECOMMENDATION"
fi


RECOMMENDATION="3.4.1.1 Ensure IPv4 default deny firewall policy (Automated)"
inputChain=$(iptables -L | grep "Chain INPUT" | awk '{print $4}')
#echo $inputChain

ForwardChain=$(iptables -L | grep "Chain FORWARD" | awk '{print $4}')
#echo $ForwardChain

OutputChain=$(iptables -L | grep "Chain OUTPUT" | awk '{print $4}' )
#echo $OutputChain

if [[ $inputChain == "DROP)" ]] && [[ $ForwardChain == "ACCEPT)" ]] && [[ $OutputChain == "DROP)" ]];
then
    echo "[PASS] $RECOMMENDATION"
    Num_Of_Checks_Passed=$((Num_Of_Checks_Passed+1))
else
    echo "[FAIL] $RECOMMENDATION"
    echo "Error Message: inputChain=$inputChain ForwardChain=$ForwardChain OutputChain=$OutputChain"
fi

RECOMMENDATION="3.4.1.2 Ensure IPv4 loopback traffic is configured (Automated)"
InputAccept=$(iptables -L INPUT -v -n | grep "ACCEPT     all" | awk '{print $8}')
#echo $InputAccept

InputDrop=$(iptables -L INPUT -v -n | grep "DROP       all" | awk '{print $8}')
#echo $InputDrop

OutputAccept=$(iptables -L OUTPUT -v -n | grep "ACCEPT     all" | awk '{print $8}')
#echo $OutputAccept

if [[ $InputAccept == "0.0.0.0/0" ]] && [[ $InputDrop == "127.0.0.0/8" ]] && [[ $OutputAccept == "0.0.0.0/0" ]];
then
    echo "[PASS] $RECOMMENDATION"
    Num_Of_Checks_Passed=$((Num_Of_Checks_Passed+1))
else
    echo "[FAIL] $RECOMMENDATION"
    echo "Error Message: InputAccept=$InputAccept InputDrop=$InputDrop OutputAccept=$OutputAccept"
fi

RECOMMENDATION="3.4.1.3 Ensure IPv4 outbound and established connections are configured (Manual)"
InputTCP=$(iptables -L INPUT -v -n | grep "ACCEPT     tcp" | grep state | awk '{print $11}')
#echo $InputTCP

InputUDP=$(iptables -L INPUT -v -n | grep "ACCEPT     udp" | awk '{print $11}')
#echo $InputUDP

InputICMP=$(iptables -L INPUT -v -n | grep "ACCEPT     icmp" | awk '{print $11}')
#echo $InputICMP

OutputTCP=$(iptables -L OUTPUT -v -n | grep "ACCEPT     tcp" | awk '{print $11}')
#echo $OutputTCP

OutputUDP=$(iptables -L OUTPUT -v -n | grep "ACCEPT     udp" | awk '{print $11}')
#echo $OutputUDP

OutputICMP=$(iptables -L OUTPUT -v -n | grep "ACCEPT     icmp" | awk '{print $11}')
#echo $OutputICMP

if [[ $InputTCP == "ESTABLISHED" ]] && [[ $InputUDP == "ESTABLISHED" ]] && [[ $InputICMP == "ESTABLISHED" ]] && [[ $OutputTCP == "NEW,ESTABLISHED" ]] && [[ $OutputUDP == "NEW,ESTABLISHED" ]] && [[ $OutputICMP == "NEW,ESTABLISHED" ]];
then
    echo "[PASS] $RECOMMENDATION"
    Num_Of_Checks_Passed=$((Num_Of_Checks_Passed+1))
else
    echo "[FAIL] $RECOMMENDATION"
    echo "Error Message: InputTCP=$InputTCP InputUDP=$InputUDP InputICMP=$InputICMP OutputTCP=$OutputTCP OutputUDP=$OutputUDP OutputICMP=$OutputICMP"
fi


RECOMMENDATION="3.4.2.1 Ensure IPv6 default deny firewall policy (Automated)"
inputChainLine=$(ip6tables -L | grep "Chain INPUT" )
inputChain=` echo $inputChainLine | awk '{print $4}' `
#echo $inputChain

ForwardChainLine=$(ip6tables -L | grep "Chain FORWARD" )
ForwardChain=` echo $ForwardChainLine | awk '{print $4}' `
#echo $ForwardChain

OutputChainLine=$(ip6tables -L | grep "Chain OUTPUT" )
OutputChain=` echo $OutputChainLine | awk '{print $4}' `
#echo $OutputChain

if [[ $inputChain == "DROP)" ]] && [[ $ForwardChain == "DROP)" ]] && [[ $OutputChain == "DROP)" ]];
then
    echo "[PASS] $RECOMMENDATION"
    Num_Of_Checks_Passed=$((Num_Of_Checks_Passed+1))
else
    echo "[FAIL] $RECOMMENDATION"
    echo "Error Message: inputChain=$inputChain ForwardChain=$ForwardChain OutputChain=$OutputChain"
fi



RECOMMENDATION="3.4.2.2 Ensure IPv6 loopback traffic is configured (Automated)"
InputAccept=$(ip6tables -L INPUT -v -n | grep "ACCEPT     all" | awk '{print $7}')
#echo $InputAccept

InputDrop=$(ip6tables -L INPUT -v -n | grep "DROP       all" | awk '{print $7}')
#echo $InputDrop

OutputAccept=$(ip6tables -L OUTPUT -v -n | grep "ACCEPT     all" | awk '{print $7}')
#echo $OutputAccept


if [[ $InputAccept == "::/0" ]] && [[ $InputDrop == "::1" ]] && [[ $OutputAccept == "::/0" ]];
then
    echo "[PASS] $RECOMMENDATION"
    Num_Of_Checks_Passed=$((Num_Of_Checks_Passed+1))
else
    echo "[FAIL] $RECOMMENDATION"
    echo "Error Message: InputAccept=$InputAccept InputDrop=$InputDrop OutputAccept=$OutputAccept"
fi


RECOMMENDATION="3.4.2.3 Ensure IPv6 outbound and established connections are configured (Manual)"
InputTCP=$(ip6tables -L INPUT -v -n | grep "ACCEPT     tcp" | grep ESTABLISHED | awk '{print $10}')
#echo $InputTCP

InputUDP=$(ip6tables -L INPUT -v -n | grep "ACCEPT     udp" | awk '{print $10}')
#echo $InputUDP

InputICMP=$(ip6tables -L INPUT -v -n | grep "ACCEPT     icmp" | awk '{print $10}')
#echo $InputICMP

OutputTCP=$(ip6tables -L OUTPUT -v -n | grep "ACCEPT     tcp" | awk '{print $10}')
#echo $OutputTCP

OutputUDP=$(ip6tables -L OUTPUT -v -n | grep "ACCEPT     udp" | awk '{print $10}')
#echo $OutputUDP

OutputICMP=$(ip6tables -L OUTPUT -v -n | grep "ACCEPT     icmp" | awk '{print $10}')
#echo $OutputICMP

if [[ $InputTCP == "ESTABLISHED" ]] && [[ $InputUDP == "ESTABLISHED" ]] && [[ $InputICMP == "ESTABLISHED" ]] && [[ $OutputTCP == "NEW,ESTABLISHED" ]] && [[ $OutputUDP == "NEW,ESTABLISHED" ]] && [[ $OutputICMP == "NEW,ESTABLISHED" ]];
then
    echo "[PASS] $RECOMMENDATION"
    Num_Of_Checks_Passed=$((Num_Of_Checks_Passed+1))
else
    echo "[FAIL] $RECOMMENDATION"
    echo "Error Message: InputTCP=$InputTCP InputUDP=$InputUDP InputICMP=$InputICMP OutputTCP=$OutputTCP OutputUDP=$OutputUDP OutputICMP=$OutputICMP"
fi

echo "$Num_Of_Checks_Passed/$Total_Num_Of_Checks checks passed"