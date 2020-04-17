title 'Trust'

describe command('Get-ADTrust -Identity "first.local"') do
    its('stdout') { should match (/first.local/) }
end