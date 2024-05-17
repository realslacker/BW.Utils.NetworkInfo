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
    [int] $CIDR = 32
    [int] $Usable = 0
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
        $this.Usable       = [math]::Pow(2,32-$this.CIDR)-2
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

}

function Get-NetworkInfo {

    [CmdletBinding()]
    [OutputType( [BWNetworkInfoObject] )]
    param(

        [Parameter( ParameterSetName='NetworkAddress', Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName )]
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
    [CmdletBinding()]
    [OutputType( [bool] )]
    param(
        
        [Parameter( Mandatory )]
        [BWNetworkInfoObject]
        $NetworkAddress,

        [Parameter( Mandatory )]
        [ipaddress]
        $IPAddress

    )

    return $NetworkAddress.Contains($IPAddress)

}