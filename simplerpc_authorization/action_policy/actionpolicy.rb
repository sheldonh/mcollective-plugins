module MCollective
    module Util
        # A class to do Simple RPC authorization checks using a per agent
        # policy file, policy files can allow or deny requests based on 
        # facts and classes on the node and the unix user id of the caller.
        #
        # A policy file gets stored in /etc/mcollective/policies/<agent>.policy
        #
        # Sample: 
        # policy default deny
        # allow    uid=500 status enable disable   country=uk     apache
        #
        # This will deny all service agent requests except for requests for
        # actions status, enable and disable on nodes with fact country=uk
        # that also have the class apache from caller userid 500.  
        #
        # Policy files can be commented with lines beginning with #, blank lines
        # are ignored.  Between each major part of the policy line should be tabs
        # you can specify multiple facts, actions and classes in space seperated lists
        #
        # Released under the Apache v2 License - R.I.Pienaar <rip@devco.net>
        class ActionPolicy
            def self.authorize(request)
                policy_allow = true

                logger = Log.instance
                configdir = Config.instance.configdir

                policyfile = "#{configdir}/policies/#{request.agent}.policy"

                logger.debug("Looking for policy in #{policyfile}")

                if File.exist?(policyfile)
                    File.open(policyfile).each do |line|
                        next if line =~ /^#/
                        next if line =~ /^$/

                        if line =~ /^policy default (.+)/
                            $1 == "allow" ? policy_allow = true : policy_allow = false

                        elsif line =~ /^(allow|deny)\t+(.+)\t+(.+)\t+(.+)\t+(.+)$/
                            policyresult =  check_policy($1, $2, $3, $4, $5, request)

                            # deny or allow the rpc request based on the policy check
                            if policyresult == true
                                if $1 == "allow"
                                    return true
                                else
                                    deny("Denying based on deny policy line match")
                                end
                            end
                        else
                            logger.debug("Cannot parse policy line: #{line}")
                        end
                    end
                end

                # If we get here then none of the policy lines matched so 
                # we should just do whatever the default policy states
                if policy_allow == true
                    return true
                else
                    deny("Denying based on default policy")
                end
            end

            private
            def self.check_policy(auth, rpccaller, actions, facts, classes, request)
                # If we are not serving the caller or action in the policy line, skip checks
                return false unless rpccaller == request.caller
                return false unless actions.split.grep(request.action).size > 0

                # Facts and Classes that do not match what we have indicates
                # that we should skip checking this auth line
                facts.split.each do |fact|
                    if fact =~ /(.+)=(.+)/
                        return false unless Util.get_fact($1) == $2
                    end
                end

                classes.split.each do |klass|
                    return false unless Util.has_cf_class?(klass)
                end

                # If we get here all the facts, classes, caller and actions match
                # our request.  We should now allow or deny it based on the auth
                # in the policy line
                if auth == "allow"
                    return true
                else
                    deny("Denying based on policy") if auth == "deny"
                end
            end

            # Logs why we are not authorizing a request then raise an appropriate
            # exception to block the action
            def self.deny(logline)
                Log.instance.debug(logline)

                raise RPCAborted, "You are not authorized to call this agent or action"
            end
        end
    end
end