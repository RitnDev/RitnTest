"""
RitnTest : client RCON / RCON client.

FR : Envoie des commandes à une partie Factorio hébergée (« Héberger une partie ») par RCON,
     et affiche la réponse. L'adresse et le mot de passe sont lus dans le config.ini de Factorio
     (local-rcon-socket, local-rcon-password) : rien de secret dans le dépôt.
EN : Sends commands to a hosted Factorio game ("Host game") through RCON,
     and prints the answer. The address and the password are read from Factorio's config.ini
     (local-rcon-socket, local-rcon-password): nothing secret inside the repository.

Utilisation / Usage :
    python rcon.py cmd "/silent-command rcon.print(game.tick)"
        FR : commande brute / EN : raw command
    python rcon.py call gvv click 1 gvv_main-button-close left
        FR : appelle remote.call("RitnTest_gvv", "click", 1, "gvv_main-button-close", "left")
        EN : calls remote.call("RitnTest_gvv", "click", 1, "gvv_main-button-close", "left")
        FR : chaque argument est écrit tel quel s'il ressemble à du Lua (nombre, true, false, nil,
             table entre {}), sinon entre guillemets.
        EN : each argument is written as is if it looks like Lua (number, true, false, nil,
             table within {}), otherwise within quotes.
    python rcon.py screenshot gvv 1 nom
        FR : capture, attend le fichier puis affiche son chemin / EN : screenshot, waits for the file then prints its path

Options :
    --factorio <dossier> : FR : dossier de Factorio / EN : Factorio folder
                           (par défaut / default : W:\\Jeux\\Factorio\\claude\\factorio-2-1)
"""

import argparse
import configparser
import os
import re
import socket
import struct
import sys
import time

# FR : Dossier de Factorio utilisé pour les tests
# EN : Factorio folder used for the tests
DEFAULT_FACTORIO = r"W:\Jeux\Factorio\claude\factorio-2-1"

# FR : Types de paquets RCON (protocole Source)
# EN : RCON packet types (Source protocol)
TYPE_AUTH = 3
TYPE_COMMAND = 2

# FR : Texte de Factorio la première fois qu'une commande Lua est utilisée dans une partie
#      (il faut la renvoyer pour qu'elle soit exécutée)
# EN : Factorio text the first time a Lua command is used in a game
#      (it must be sent again to be run)
ACHIEVEMENTS_WARNING = "achievements"


def read_config(factorio_folder):
    """FR : Adresse, port et mot de passe RCON lus dans config.ini.
    EN : RCON address, port and password read from config.ini."""
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.read(os.path.join(factorio_folder, "config", "config.ini"), encoding="utf-8")

    # FR : Valeurs de la section [other]
    # EN : Values of the [other] section
    socket_text = parser.get("other", "local-rcon-socket", fallback="")
    password = parser.get("other", "local-rcon-password", fallback="")
    if not socket_text:
        sys.exit("RitnTest: local-rcon-socket is not set in config.ini")

    # FR : « 127.0.0.1:27015 » donne l'adresse et le port
    # EN : "127.0.0.1:27015" gives the address and the port
    host, port = socket_text.rsplit(":", 1)
    return host, int(port), password


def send_packet(connection, packet_id, packet_type, body):
    """FR : Envoie un paquet RCON : taille, id, type, texte, deux octets nuls.
    EN : Sends an RCON packet: size, id, type, text, two null bytes."""
    payload = struct.pack("<ii", packet_id, packet_type) + body.encode("utf-8") + b"\x00\x00"
    connection.sendall(struct.pack("<i", len(payload)) + payload)


def receive_exact(connection, size):
    """FR : Lit exactement size octets.
    EN : Reads exactly size bytes."""
    data = b""
    while len(data) < size:
        chunk = connection.recv(size - len(data))
        if not chunk:
            raise ConnectionError("RitnTest: connection closed by Factorio")
        data += chunk
    return data


def receive_packet(connection):
    """FR : Lit un paquet RCON : renvoie son id et son texte.
    EN : Reads an RCON packet: returns its id and its text."""
    size = struct.unpack("<i", receive_exact(connection, 4))[0]
    payload = receive_exact(connection, size)
    packet_id = struct.unpack("<i", payload[0:4])[0]
    body = payload[8:-2].decode("utf-8", errors="replace")
    return packet_id, body


class Rcon:
    """FR : Connexion RCON authentifiée.
    EN : Authenticated RCON connection."""

    def __init__(self, factorio_folder):
        host, port, password = read_config(factorio_folder)

        # FR : Connexion, puis authentification (Factorio renvoie l'id -1 si le mot de passe est faux)
        # EN : Connection, then authentication (Factorio answers with id -1 if the password is wrong)
        self.connection = socket.create_connection((host, port), timeout=10)
        self.next_id = 1
        send_packet(self.connection, self.next_id, TYPE_AUTH, password)
        packet_id, _ = receive_packet(self.connection)
        if packet_id == -1:
            sys.exit("RitnTest: wrong RCON password")

    def command(self, text):
        """FR : Envoie une commande et renvoie la réponse. Renvoyée une fois si Factorio prévient
        que les succès seront désactivés (première commande Lua de la partie).
        EN : Sends a command and returns the answer. Sent again once if Factorio warns
        that achievements will be disabled (first Lua command of the game)."""
        answer = self._send(text)
        if ACHIEVEMENTS_WARNING in answer.lower() and text.startswith("/"):
            answer = self._send(text)
        return answer

    def _send(self, text):
        self.next_id += 1
        send_packet(self.connection, self.next_id, TYPE_COMMAND, text)
        _, body = receive_packet(self.connection)
        return body

    def close(self):
        self.connection.close()


def lua_argument(text):
    """FR : Argument en Lua : tel quel s'il en a l'air, sinon chaîne entre guillemets.
    EN : Argument as Lua: as is if it looks like it, otherwise string within quotes."""
    if re.fullmatch(r"-?\d+(\.\d+)?|true|false|nil|\{.*\}", text, re.DOTALL):
        return text
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"').replace("\r", "\\r").replace("\n", "\\n") + '"'


def remote_call_command(mod_name, function, arguments):
    """FR : Commande qui appelle l'interface RitnTest du mod et affiche le résultat.
    EN : Command that calls the mod RitnTest interface and prints the result."""
    lua_arguments = "".join(", " + lua_argument(argument) for argument in arguments)
    # FR : Un texte est affiché tel quel (retours à la ligne compris), le reste en une ligne
    # EN : A text is printed as is (line breaks included), the rest on one line
    return ('/silent-command local r = remote.call("RitnTest_%s", "%s"%s) '
            'rcon.print(type(r) == "string" and r or serpent.line(r, {comment = false}))'
            % (mod_name, function, lua_arguments))


def main():
    parser = argparse.ArgumentParser(description="RitnTest RCON client")
    parser.add_argument("--factorio", default=DEFAULT_FACTORIO)
    sub = parser.add_subparsers(dest="mode", required=True)

    # FR : Commande brute / EN : Raw command
    raw = sub.add_parser("cmd")
    raw.add_argument("text")

    # FR : Appel de l'interface d'un mod / EN : Call of a mod interface
    call = sub.add_parser("call")
    call.add_argument("mod")
    call.add_argument("function")
    call.add_argument("arguments", nargs="*")

    # FR : Capture d'écran / EN : Screenshot
    shot = sub.add_parser("screenshot")
    shot.add_argument("mod")
    shot.add_argument("player_index")
    shot.add_argument("name")

    options = parser.parse_args()
    rcon = Rcon(options.factorio)
    try:
        if options.mode == "cmd":
            print(rcon.command(options.text))
        elif options.mode == "call":
            print(rcon.command(remote_call_command(options.mod, options.function, options.arguments)))
        else:
            # FR : Ancien fichier retiré, capture demandée, puis attente du nouveau fichier
            # EN : Old file removed, screenshot requested, then wait for the new file
            path = os.path.join(options.factorio, "script-output", "RitnTest", options.name + ".png")
            if os.path.exists(path):
                os.remove(path)
            print(rcon.command(remote_call_command(options.mod, "screenshot", [options.player_index, options.name])))
            for _ in range(100):
                if os.path.exists(path):
                    time.sleep(0.3)
                    print(path)
                    break
                time.sleep(0.1)
            else:
                print("RitnTest: screenshot not written (is the game paused?)")
    finally:
        rcon.close()


if __name__ == "__main__":
    main()
