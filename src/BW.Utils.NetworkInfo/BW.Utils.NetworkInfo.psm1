enum BWNetworkInfoFormat {
    IPAddress
    IPAddressWithCIDR
    IPAddressWithMask
    Network
    NetworkWithCIDR
    NetworkWithMask
    SubnetMask
    CIDR
}

class BWNetworkInfoObject:IComparable {

    [ipaddress] $IPAddress
    [ipaddress] $Network
    [ipaddress] $Broadcast
    [ipaddress] $SubnetMask
    [ipaddress] $WildcardMask
    [ValidateRange(0,32)]
    [UInt32] $CIDR = 32
    [UInt32] $Addresses = 0
    [UInt32] $Usable = 0
    [ipaddress] $FirstUsable
    [ipaddress] $LastUsable

    BWNetworkInfoObject( [string] $NetworkAddress ) {
        $this.IPAddress, [string]$Mask = $NetworkAddress.Split('/',2)
        if ( -not $Mask ) {
            $this.SubnetMask = '255.255.255.255'
            $this.CIDR = 32
        }
        elseif ( $Mask.IndexOf('.') -eq -1 ) {
            $this.SubnetMask = [BWNetworkInfoObject]::CIDRToSubnetMask($Mask)
            $this.CIDR       = $Mask
        }
        else {
            $this.SubnetMask = $Mask
            $this.CIDR = [BWNetworkInfoObject]::SubnetMaskToCIDR($Mask)
        }
        $this.__InitObject()
    }

    BWNetworkInfoObject( [ipaddress] $IPAddress, [int] $CIDR ) {
        $this.IPAddress  = $IPAddress
        $this.SubnetMask = [BWNetworkInfoObject]::CIDRToSubnetMask($CIDR)
        $this.CIDR       = $CIDR
        $this.__InitObject()
    }

    BWNetworkInfoObject( [ipaddress] $IPAddress, [ipaddress] $SubnetMask ) {
        $this.IPAddress  = $IPAddress
        $this.SubnetMask = $SubnetMask
        $this.CIDR       = [BWNetworkInfoObject]::SubnetMaskToCIDR($SubnetMask)
        $this.__InitObject()
    }

    hidden [void] __InitObject() {
        if ( $this.CIDR -in @(0,32) ) { return }
        $this.WildcardMask = 4294967295 -bxor $This.SubnetMask.Address
        $this.Network      = $this.IPAddress.Address -band $this.SubnetMask.Address
        $this.Broadcast    = $this.WildcardMask.Address -bor $this.Network.Address
        $this.Addresses    = [math]::Pow(2,32-$this.CIDR)
        $this.Usable       = $this.Addresses - 2
        $this.FirstUsable  = $this.Network.Address + 16777216
        $this.LastUsable   = $this.Broadcast.Address - 16777216
    }

    static [int] SubnetMaskToCIDR( [string] $SubnetMask ) {
        $StringCIDR = $SubnetMask.Split('.').ForEach({ [convert]::ToString($_,2).PadLeft(8,'0') }) -join ''
        if ( $StringCidr.TrimEnd('0').IndexOf('0') -ne -1 ) {
            throw 'Invalid subnet mask'
        }
        return $StringCidr.Trim('0').Length
    }

    static [ipaddress] CIDRToSubnetMask( [int] $CIDR ) {
        if ( $CIDR -gt 32 ) { throw 'Invalid CIDR' }
        return [ipaddress][BitConverter]::ToUInt32( [BitConverter]::GetBytes( [convert]::ToUInt32( ( '1' * $CIDR ).PadRight( 32, '0'), 2 ) )[3..0], 0 )
    }

    [string] ToString( [BWNetworkInfoFormat] $BWNetworkInfoFormat ) {
        $Result = switch ( [string] $BWNetworkInfoFormat ) {
            'IPAddress'         { $this.IPAddress }
            'IPAddressWithCIDR' { $this.IPAddress, $this.CIDR -join '/' }
            'IPAddressWithMask' { $this.IPAddress, $this.SubnetMask -join '/' }
            'Network'           { $this.Network }
            'NetworkWithCIDR'   { $this.Network, $this.CIDR -join '/' }
            'NetworkWithMask'   { $this.Network, $this.SubnetMask -join '/' }
            'SubnetMask'        { $this.SubnetMask }
            'CIDR'              { $this.CIDR }
            default             { throw 'Invalid Format' }
        }
        return [string] $Result
    }

    [string] ToString() {
        return $this.ToString( 'IPAddressWithCIDR' )
    }

    [bool] Contains( [ipaddress] $IPAddress ) {
        return (
            [ipaddress]::NetworkToHostOrder($this.Network.Address) -le [ipaddress]::NetworkToHostOrder($IPAddress.Address) -and
            [ipaddress]::NetworkToHostOrder($IPAddress.Address) -le [ipaddress]::NetworkToHostOrder($this.Broadcast.Address)
        )
    }

    [bool] Equals( $that ) {
        [BWNetworkInfoObject] $that = $that
        return $this.IPAddress -eq $that.IPAddress -and $this.CIDR -eq $that.CIDR
    }

    [int] CompareTo( $that ) {
        [BWNetworkInfoObject] $that = $that
        return ( -1, 1 )[[ipaddress]::NetworkToHostOrder($this.IPAddress.Address) -gt [ipaddress]::NetworkToHostOrder($that.IPAddress.Address)]
    }

    static [BWNetworkInfoObject] op_Addition( [BWNetworkInfoObject] $NetworkInfoObject, [UInt32] $IncrementAmount ) {
        [byte[]] $Octets = $NetworkInfoObject.IPAddress.GetAddressBytes()
        [array]::Reverse($Octets)
        for ( $i = 0; $i -lt $Octets.Length; $i ++ ) {
            try {
                $Octets[$i] += $IncrementAmount
                break
            } catch {
                $Octets[$i] = 0
            }
        }
        [array]::Reverse($Octets)
        $NextIPAddress = [ipaddress] $Octets
        if ( $NetworkInfoObject.Contains($NextIPAddress) -or $NetworkInfoObject.CIDR -in @(0,32) ) {
            return [BWNetworkInfoObject]::new($NextIPAddress, $NetworkInfoObject.CIDR)
        }
        throw ( 'Network {0} does not contain {1}' -f $NetworkInfoObject, $NextIPAddress )
    }

    static [BWNetworkInfoObject] op_Subtraction( [BWNetworkInfoObject] $NetworkInfoObject, [UInt32] $DecrementAmount ) {
        [byte[]] $Octets = $NetworkInfoObject.IPAddress.GetAddressBytes()
        [array]::Reverse($Octets)
        for ( $i = 0; $i -lt $Octets.Length; $i ++ ) {
            try {
                $Octets[$i] -= $DecrementAmount
                break
            } catch {
                $Octets[$i] = 255
            }
        }
        [array]::Reverse($Octets)
        $NextIPAddress = [ipaddress] $Octets
        if ( $NetworkInfoObject.Contains($NextIPAddress) -or $NetworkInfoObject.CIDR -in @(0,32) ) {
            return [BWNetworkInfoObject]::new($NextIPAddress, $NetworkInfoObject.CIDR)
        }
        throw ( 'Network {0} does not contain {1}' -f $NetworkInfoObject, $NextIPAddress )
    }

}

function Get-NetworkInfo {
    <#
    .SYNOPSIS
    Get information about a network based on the IP address and netmask
    .PARAMETER NetworkAddress
    Network address formatted 0.0.0.0/0
    .PARAMETER IPAddress
    IP address formatted 0.0.0.0
    .PARAMETER SubnetMask
    Subnet mask formatted 0.0.0.0
    .PARAMETER CIDR
    CIDR mask in integer format
    .EXAMPLE
    Get-NetworkInfo '192.168.1.0/25'
    .EXAMPLE
    Get-NetworkInfo -IPAddress '192.168.1.0' -SubnetMask '255.255.255.128'
    .EXAMPLE
    Get-NetworkInfo -IPAddress '192.168.1.0' -CIDR 25
    .EXAMPLE
    '192.168.1.0/25' | Get-NetworkInfo
    #>
    [CmdletBinding()]
    [OutputType( [BWNetworkInfoObject] )]
    param(

        [Parameter( ParameterSetName='NetworkAddress', Mandatory, ValueFromPipeline, Position = 0 )]
        [string]
        $NetworkAddress,

        [Parameter( ParameterSetName='IPAddress', Mandatory )]
        [Parameter( ParameterSetName='IPAddressWithSubnet', Mandatory )]
        [Parameter( ParameterSetName='IPAddressWithCIDR', Mandatory )]
        [ipaddress]
        $IPAddress,

        [Parameter( ParameterSetName='IPAddressWithSubnet', Mandatory )]
        [ipaddress]
        $SubnetMask,

        [Parameter( ParameterSetName='IPAddressWithCIDR', Mandatory )]
        [ValidateRange(0,32)]
        [int]
        $CIDR

    )

    process {

        switch ( $PSCmdlet.ParameterSetName ) {
            'NetworkAddress'      { [BWNetworkInfoObject]::new( $NetworkAddress ) }
            'IPAddressWithSubnet' { [BWNetworkInfoObject]::new( $IPAddress, $SubnetMask ) }
            default               { [BWNetworkInfoObject]::new( $IPAddress, $CIDR ) }
        }
    
    }
    
}

function Test-NetworkContains {
    <#
    .SYNOPSIS
    Test if a network contains an IP address
    .PARAMETER NetworkAddress
    The network to test
    .PARAMETER IPAddress
    The IP address to check against the network
    .EXAMPLE
    Test-NetworkContains -NetworkAddress '192.168.1.0/25' -IPAddress '192.168.1.1' # returns $true
    .EXAMPLE
    Test-NetworkContains '192.168.1.0/25' '192.168.1.128' # returns $false
    .EXAMPLE
    '192.168.1.0/25' | Test-NetworkContains -IPAddress '192.168.1.1' # returns $true
    #>
    [CmdletBinding()]
    [OutputType( [bool] )]
    param(
        
        [Parameter( Mandatory, ValueFromPipeline, Position = 0 )]
        [BWNetworkInfoObject]
        $NetworkAddress,

        [Parameter( Mandatory, Position = 1 )]
        [ipaddress]
        $IPAddress

    )

    return $NetworkAddress.Contains($IPAddress)

}
