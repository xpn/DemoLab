title 'Trust'

describe command('Get-ADTrust -Identity "second.local"') do
    its('stdout') { should match (/second.local/) }
end