
use Kernel::System::Ticket;

package Kernel::System::Ticket;

use strict;
use warnings;
use Data::Dumper;

sub TicketCreate {

    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Needed (qw(OwnerID UserID)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!"
            );
            return;
        }
    }

    my $ArchiveFlag = 0;
    if ( $Param{ArchiveFlag} && $Param{ArchiveFlag} eq 'y' ) {
        $ArchiveFlag = 1;
    }

    $Param{ResponsibleID} ||= 1;

    # get type object
    my $TypeObject = $Kernel::OM->Get('Kernel::System::Type');

    if ( !$Param{TypeID} && !$Param{Type} ) {

        # get default ticket type
        my $DefaultTicketType = $Kernel::OM->Get('Kernel::Config')->Get('Ticket::Type::Default');

        # check if default ticket type exists
        my %AllTicketTypes = reverse $TypeObject->TypeList();

        if ( $AllTicketTypes{$DefaultTicketType} ) {
            $Param{Type} = $DefaultTicketType;
        }
        else {
            $Param{TypeID} = 1;
        }
    }

    # TypeID/Type lookup!
    if ( !$Param{TypeID} && $Param{Type} ) {
        $Param{TypeID} = $TypeObject->TypeLookup( Type => $Param{Type} );
    }
    elsif ( $Param{TypeID} && !$Param{Type} ) {
        $Param{Type} = $TypeObject->TypeLookup( TypeID => $Param{TypeID} );
    }
    if ( !$Param{TypeID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "No TypeID for '$Param{Type}'!",
        );
        return;
    }

    # get queue object
    my $QueueObject = $Kernel::OM->Get('Kernel::System::Queue');

    # QueueID/Queue lookup!
    if ( !$Param{QueueID} && $Param{Queue} ) {
        $Param{QueueID} = $QueueObject->QueueLookup( Queue => $Param{Queue} );
    }
    elsif ( !$Param{Queue} ) {
        $Param{Queue} = $QueueObject->QueueLookup( QueueID => $Param{QueueID} );
    }
    if ( !$Param{QueueID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "No QueueID for '$Param{Queue}'!",
        );
        return;
    }

    # get state object
    my $StateObject = $Kernel::OM->Get('Kernel::System::State');

    # StateID/State lookup!
    if ( !$Param{StateID} ) {
        my %State = $StateObject->StateGet( Name => $Param{State} );
        $Param{StateID} = $State{ID};
    }
    elsif ( !$Param{State} ) {
        my %State = $StateObject->StateGet( ID => $Param{StateID} );
        $Param{State} = $State{Name};
    }
    if ( !$Param{StateID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "No StateID for '$Param{State}'!",
        );
        return;
    }

    # LockID lookup!
    if ( !$Param{LockID} && $Param{Lock} ) {

        $Param{LockID} = $Kernel::OM->Get('Kernel::System::Lock')->LockLookup(
            Lock => $Param{Lock},
        );
    }
    if ( !$Param{LockID} && !$Param{Lock} ) {

        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'No LockID and no LockType!',
        );
        return;
    }

    # get priority object
    my $PriorityObject = $Kernel::OM->Get('Kernel::System::Priority');

    # PriorityID/Priority lookup!
    if ( !$Param{PriorityID} && $Param{Priority} ) {
        $Param{PriorityID} = $PriorityObject->PriorityLookup(
            Priority => $Param{Priority},
        );
    }
    elsif ( $Param{PriorityID} && !$Param{Priority} ) {
        $Param{Priority} = $PriorityObject->PriorityLookup(
            PriorityID => $Param{PriorityID},
        );
    }
    if ( !$Param{PriorityID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'No PriorityID (invalid Priority Name?)!',
        );
        return;
    }

    # get service object
    my $ServiceObject = $Kernel::OM->Get('Kernel::System::Service');

    # ServiceID/Service lookup!
    if ( !$Param{ServiceID} && $Param{Service} ) {
        $Param{ServiceID} = $ServiceObject->ServiceLookup(
            Name => $Param{Service},
        );
    }
    elsif ( $Param{ServiceID} && !$Param{Service} ) {
        $Param{Service} = $ServiceObject->ServiceLookup(
            ServiceID => $Param{ServiceID},
        );
    }

    # get sla object
    my $SLAObject = $Kernel::OM->Get('Kernel::System::SLA');

    # SLAID/SLA lookup!
    if ( !$Param{SLAID} && $Param{SLA} ) {
        $Param{SLAID} = $SLAObject->SLALookup( Name => $Param{SLA} );
    }
    elsif ( $Param{SLAID} && !$Param{SLA} ) {
        $Param{SLA} = $SLAObject->SLALookup( SLAID => $Param{SLAID} );
    }

    # create ticket number if none is given
    if ( !$Param{TN} ) {
        $Param{TN} = $Self->TicketCreateNumber();
    }

    # check ticket title
    if ( !defined $Param{Title} ) {
        $Param{Title} = '';
    }

    # substitute title if needed
    else {
        $Param{Title} = substr( $Param{Title}, 0, 255 );
    }

    # [Complemento] Change ticket queue based on service preference
    if ($Param{ServiceID}) {

        my %Preferences = $Kernel::OM->Get('Kernel::System::Service')->ServicePreferencesGet(
            ServiceID => $Param{ServiceID},
            UserID    => 1,
        );
        if ($Preferences{TicketQueue}) {

            if($Preferences{TicketQueue} eq '0-Expression') {

                if ($Preferences{TicketQueueExpression} =~ m{<OTRS_TICKET_([A-Za-z0-9_]+)>}msxi) {

                    my $TicketAttribute = $1;
                    if ( $TicketAttribute =~ m{DynamicField_(\S+?)_Value} ) {

                        my $DynamicFieldName                = $1;
                        my $ParamObject                     = $Kernel::OM->Get('Kernel::System::Web::Request');
                        $Preferences{TicketQueueExpression} = $ParamObject->GetParam( Param => "DynamicField_$DynamicFieldName" );

                    } elsif ($Param{$TicketAttribute}) {

                        $Preferences{TicketQueueExpression} = $Param{$TicketAttribute};

                    }
                }

                my $QueueID = $Kernel::OM->Get('Kernel::System::Queue')->QueueLookup( Queue => $Preferences{TicketQueueExpression} )||0;
                if ($QueueID) {

                    $Param{QueueID} = $QueueID;
                    $Param{Queue}   = $QueueObject->QueueLookup( QueueID => $Param{QueueID} );

                }

            } else {
            
                $Param{QueueID} = $Preferences{TicketQueue};
                $Param{Queue}   = $QueueObject->QueueLookup( QueueID => $Param{QueueID} );

            }
        }
    }

    # check database undef/NULL (set value to undef/NULL to prevent database errors)
    $Param{ServiceID} ||= undef;
    $Param{SLAID}     ||= undef;

    # create db record
    return if !$Kernel::OM->Get('Kernel::System::DB')->Do(
        SQL => '
            INSERT INTO ticket (tn, title, type_id, queue_id, ticket_lock_id,
                user_id, responsible_user_id, ticket_priority_id, ticket_state_id,
                escalation_time, escalation_update_time, escalation_response_time,
                escalation_solution_time, timeout, service_id, sla_id, until_time,
                archive_flag, create_time, create_by, change_time, change_by)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0, 0, 0, 0, ?, ?, 0, ?,
                current_timestamp, ?, current_timestamp, ?)',
        Bind => [
            \$Param{TN}, \$Param{Title}, \$Param{TypeID}, \$Param{QueueID},
            \$Param{LockID},     \$Param{OwnerID}, \$Param{ResponsibleID},
            \$Param{PriorityID}, \$Param{StateID}, \$Param{ServiceID},
            \$Param{SLAID}, \$ArchiveFlag, \$Param{UserID}, \$Param{UserID},
        ],
    );

    # get ticket id
    my $TicketID = $Self->TicketIDLookup(
        TicketNumber => $Param{TN},
        UserID       => $Param{UserID},
    );

    # add history entry
    $Self->HistoryAdd(
        TicketID     => $TicketID,
        QueueID      => $Param{QueueID},
        HistoryType  => 'NewTicket',
        Name         => "\%\%$Param{TN}\%\%$Param{Queue}\%\%$Param{Priority}\%\%$Param{State}\%\%$TicketID",
        CreateUserID => $Param{UserID},
    );

    if ( $Kernel::OM->Get('Kernel::Config')->Get('Ticket::Service') ) {

        # history insert for service so that initial values can be seen
        my $HistoryService   = $Param{Service}   || 'NULL';
        my $HistoryServiceID = $Param{ServiceID} || '';
        $Self->HistoryAdd(
            TicketID     => $TicketID,
            HistoryType  => 'ServiceUpdate',
            Name         => "\%\%$HistoryService\%\%$HistoryServiceID\%\%NULL\%\%",
            CreateUserID => $Param{UserID},
        );

        # history insert for SLA
        my $HistorySLA   = $Param{SLA}   || 'NULL';
        my $HistorySLAID = $Param{SLAID} || '';
        $Self->HistoryAdd(
            TicketID     => $TicketID,
            HistoryType  => 'SLAUpdate',
            Name         => "\%\%$HistorySLA\%\%$HistorySLAID\%\%NULL\%\%",
            CreateUserID => $Param{UserID},
        );
    }

    if ( $Kernel::OM->Get('Kernel::Config')->Get('Ticket::Type') ) {

        # Insert history record for ticket type, so that initial value can be seen.
        #   Please see bug#12702 for more information.
        $Self->HistoryAdd(
            TicketID     => $TicketID,
            HistoryType  => 'TypeUpdate',
            Name         => "\%\%$Param{Type}\%\%$Param{TypeID}",
            CreateUserID => $Param{UserID},
        );
    }

    # set customer data if given
    if ( $Param{CustomerNo} || $Param{CustomerID} || $Param{CustomerUser} ) {
        $Self->TicketCustomerSet(
            TicketID => $TicketID,
            No       => $Param{CustomerNo} || $Param{CustomerID} || '',
            User     => $Param{CustomerUser} || '',
            UserID   => $Param{UserID},
        );
    }

    # update ticket view index
    $Self->TicketAcceleratorAdd( TicketID => $TicketID );

    # log ticket creation
    $Kernel::OM->Get('Kernel::System::Log')->Log(
        Priority => 'info',
        Message  => "New Ticket [$Param{TN}/" . substr( $Param{Title}, 0, 15 ) . "] created "
            . "(TicketID=$TicketID,Queue=$Param{Queue},Priority=$Param{Priority},State=$Param{State})",
    );

    # trigger event
    $Self->EventHandler(
        Event => 'TicketCreate',
        Data  => {
            TicketID => $TicketID,
        },
        UserID => $Param{UserID},
    );

    return $TicketID;

}

1;
