title 'Features'

describe windows_feature('AD-Domain-Services') do
    it { should be_installed }
end

describe windows_feature('RSAT-ADDS') do
    it { should be_installed }
end