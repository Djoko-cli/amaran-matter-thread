"""Imite un port serie (PortSerie) pour les tests : lignes a rendre, octets ecrits."""


class PortFactice:
    def __init__(self, reponses=()):
        self.reponses = list(reponses)
        self.ecrit = []

    def write(self, octets):
        self.ecrit.append(octets.decode())

    def readline(self):
        return (self.reponses.pop(0) + "\r\n").encode() if self.reponses else b""
